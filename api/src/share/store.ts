// SPDX-License-Identifier: AGPL-3.0-only
import { randomInt } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

/**
 * Share storage.
 *
 * `node:sqlite` is part of stock Node, which is the whole point: the service
 * must run as a plain `node dist/server.js` with no compiled dependencies.
 */

export type ShareKind = 'route' | 'ride';

export interface ShareSummary {
  distance_km: number;
  ascent_m?: number;
  duration_s?: number;
}

export interface ShareRecord {
  id: string;
  kind: ShareKind;
  name: string;
  gpx: string;
  summary: ShareSummary;
  createdAt: number;
  expiresAt: number;
}

export const SHARE_TTL_MS = 365 * 24 * 60 * 60 * 1000;

const BASE62 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
const ID_LENGTH = 10;

/** 10 base62 characters ~ 59 bits; collisions are handled by retrying the insert. */
export function randomId(length = ID_LENGTH): string {
  let out = '';
  for (let i = 0; i < length; i += 1) out += BASE62[randomInt(BASE62.length)];
  return out;
}

/** Share ids appear in URLs; validate before they reach a SQL parameter or HTML. */
export function isValidShareId(id: string): boolean {
  return id.length === ID_LENGTH && /^[A-Za-z0-9]+$/.test(id);
}

interface ShareRow {
  id: string;
  kind: string;
  name: string;
  gpx: string;
  summary_json: string;
  created_at: number;
  expires_at: number;
}

export class ShareStore {
  readonly #db: DatabaseSync;
  readonly #now: () => number;

  constructor(path: string, now: () => number = Date.now) {
    if (path !== ':memory:') {
      // SHARE_DB_PATH defaults to ./data/share.sqlite; the directory is in
      // .gitignore and may not exist on a fresh deploy.
      mkdirSync(dirname(path), { recursive: true });
    }
    this.#db = new DatabaseSync(path);
    this.#now = now;

    // WAL keeps the daily sweep from blocking readers.
    this.#db.exec('PRAGMA journal_mode = WAL');
    this.#db.exec('PRAGMA busy_timeout = 5000');
    this.#db.exec(`
      CREATE TABLE IF NOT EXISTS shares (
        id           TEXT PRIMARY KEY,
        kind         TEXT NOT NULL,
        name         TEXT NOT NULL,
        gpx          TEXT NOT NULL,
        summary_json TEXT NOT NULL,
        created_at   INTEGER NOT NULL,
        expires_at   INTEGER NOT NULL
      ) STRICT;
    `);
    this.#db.exec('CREATE INDEX IF NOT EXISTS shares_expires_at ON shares (expires_at)');
  }

  create(input: {
    kind: ShareKind;
    name: string;
    gpx: string;
    summary: ShareSummary;
  }): ShareRecord {
    const createdAt = this.#now();
    const expiresAt = createdAt + SHARE_TTL_MS;
    const summaryJson = JSON.stringify(input.summary);
    const insert = this.#db.prepare(
      `INSERT INTO shares (id, kind, name, gpx, summary_json, created_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    );

    // Retry on the (vanishingly unlikely) id collision rather than trusting luck.
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const id = randomId();
      try {
        insert.run(id, input.kind, input.name, input.gpx, summaryJson, createdAt, expiresAt);
        return { id, ...input, createdAt, expiresAt };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        if (!message.includes('UNIQUE')) throw err;
      }
    }
    throw new Error('Could not allocate a unique share id.');
  }

  /** Returns null for unknown *and* expired ids: both are a 404 to the caller. */
  get(id: string): ShareRecord | null {
    if (!isValidShareId(id)) return null;
    const row = this.#db
      .prepare('SELECT * FROM shares WHERE id = ? AND expires_at > ?')
      .get(id, this.#now()) as ShareRow | undefined;
    if (row === undefined) return null;

    let summary: ShareSummary;
    try {
      summary = JSON.parse(row.summary_json) as ShareSummary;
    } catch {
      summary = { distance_km: 0 };
    }
    return {
      id: row.id,
      kind: row.kind === 'ride' ? 'ride' : 'route',
      name: row.name,
      gpx: row.gpx,
      summary,
      createdAt: row.created_at,
      expiresAt: row.expires_at,
    };
  }

  /** Delete every expired row. Returns how many were removed. */
  sweep(): number {
    const result = this.#db.prepare('DELETE FROM shares WHERE expires_at <= ?').run(this.#now());
    return Number(result.changes);
  }

  close(): void {
    this.#db.close();
  }
}

const SWEEP_INTERVAL_MS = 24 * 60 * 60 * 1000;

/**
 * Start the daily expiry sweep. The timer is unref'd so it never keeps the
 * process alive during a graceful shutdown.
 */
export function startSweep(
  store: ShareStore,
  onSwept?: (deleted: number) => void,
): () => void {
  const run = (): void => {
    try {
      const deleted = store.sweep();
      if (deleted > 0) onSwept?.(deleted);
    } catch {
      // A failed sweep is not worth taking the service down for; the next
      // run will try again and expired rows are already invisible to readers.
    }
  };
  run();
  const timer = setInterval(run, SWEEP_INTERVAL_MS);
  timer.unref();
  return () => {
    clearInterval(timer);
  };
}
