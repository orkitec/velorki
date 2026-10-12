// SPDX-License-Identifier: AGPL-3.0-only
import { mkdir, readdir, readFile, rename, unlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { Counters } from '@/server/counters';
import { GRID_VERSION, decodeOperaTiff, parseGrid, serialiseGrid, type ClassGrid } from './grid';
import { classesOfArea, encodeClassPng, type MercatorBox } from './render';

/**
 * The OPERA radar composite, fetched lazily from EUMETNET's open bucket and
 * kept on this box.
 *
 * - The frames: the bucket's listing of the last [OPERA_HISTORY_MS], one
 *   S3 ListObjectsV2 per UTC hour it spans, shared by the cluster for
 *   [LISTING_TTL_S] through the counters.
 * - A frame's grid: the first request that needs one fetches its GeoTIFF
 *   once, decodes it into the class grid (`grid.ts`) and writes it to [dir];
 *   every later request, on any worker, reads it from there. In one worker
 *   a request already fetching is joined; across workers a lock in the
 *   counters lets one fetch while the others wait for its file. Files older
 *   than [OPERA_KEEP_MS] are deleted whenever a new one is written, so the
 *   directory holds some 30 grids of a few hundred KB.
 * - In memory, per worker: the last [GRIDS_IN_MEMORY] grids decoded (17 MB
 *   each) and the images drawn, up to [IMAGE_CACHE_BYTES].
 *
 * No timer and no cron: nothing is fetched that no rider asked for.
 */

/** The bucket, anonymous and read-only. */
export const OPERA_BUCKET = 'https://s3.waw3-1.cloudferro.com/openradar-24h';

/** The credit the app shows with the layer. */
export const OPERA_ATTRIBUTION = 'Radar: EUMETNET OPERA (CC BY 4.0)';

/** How far back the frames are offered. */
export const OPERA_HISTORY_MS = 2 * 60 * 60 * 1000;
/** How long a frame's grid stays on disk. */
export const OPERA_KEEP_MS = 150 * 60 * 1000;
/** The composite's step. */
export const OPERA_STEP_MS = 5 * 60 * 1000;

const LISTING_TTL_S = 60;
const LISTING_KEY = 'opera:frames';
const LISTING_FAIL_KEY = 'opera:frames:fail';
/** How many frames one worker fetches from the bucket at once. */
const MAX_FETCHES = 2;
const LOCK_TTL_S = 60;
const LOCK_WAIT_MS = 30_000;
const LOCK_POLL_MS = 250;
/** How long a frame that failed is not asked for again. */
const FAIL_TTL_S = 30;
const FETCH_TIMEOUT_MS = 30_000;
const LIST_TIMEOUT_MS = 10_000;
/** A composite file is some 3 MB; refuse anything absurd. */
const MAX_TIFF_BYTES = 32 * 1024 * 1024;
const GRIDS_IN_MEMORY = 2;
const IMAGE_CACHE_BYTES = 32 * 1024 * 1024;

/** A failure of the bucket: the route answers 502. */
export class OperaUpstreamError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'OperaUpstreamError';
  }
}

export interface OperaStoreOptions {
  dir: string;
  counters: Counters;
  userAgent: string;
  now?: () => number;
  /** For tests; `globalThis.fetch` at call time otherwise. */
  fetch?: typeof fetch;
  log?: { info: (obj: object, msg: string) => void; warn: (obj: object, msg: string) => void };
}

function pad(n: number, width = 2): string {
  return String(n).padStart(width, '0');
}

/** `YYYYMMDDTHHMM` of an epoch ms, UTC: the stamp the bucket's names carry. */
export function operaStamp(ms: number): string {
  const d = new Date(ms);
  return (
    `${String(d.getUTCFullYear())}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}` +
    `T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}`
  );
}

function dayPath(ms: number): string {
  const d = new Date(ms);
  return `${String(d.getUTCFullYear())}/${pad(d.getUTCMonth() + 1)}/${pad(d.getUTCDate())}`;
}

/** The bucket key of the reflectivity composite at `ms`. */
export function operaKey(ms: number): string {
  return `${dayPath(ms)}/OPERA/COMP/OPERA@${operaStamp(ms)}@0@DBZH.tiff`;
}

const KEY_RE = /<Key>(\d{4}\/\d{2}\/\d{2}\/OPERA\/COMP\/OPERA@(\d{8}T\d{4})@0@DBZH\.tiff)<\/Key>/g;

/** The frame times, epoch ms, an S3 listing names. */
export function parseListing(xml: string): number[] {
  const out: number[] = [];
  for (const m of xml.matchAll(KEY_RE)) {
    const s = m[2] ?? '';
    const ms = Date.UTC(
      Number(s.slice(0, 4)),
      Number(s.slice(4, 6)) - 1,
      Number(s.slice(6, 8)),
      Number(s.slice(9, 11)),
      Number(s.slice(11, 13)),
    );
    if (Number.isFinite(ms)) out.push(ms);
  }
  return out;
}

export class OperaStore {
  readonly #dir: string;
  readonly #counters: Counters;
  readonly #userAgent: string;
  readonly #now: () => number;
  readonly #fetch: typeof fetch;
  readonly #log: OperaStoreOptions['log'];
  readonly #inFlight = new Map<number, Promise<ClassGrid>>();
  readonly #grids = new Map<number, ClassGrid>();
  readonly #images = new Map<string, Buffer>();
  #imageBytes = 0;
  #listing: { at: number; frames: number[] } | undefined;
  #listingInFlight: Promise<number[]> | undefined;
  #fetching = 0;
  readonly #queue: (() => void)[] = [];

  constructor(opts: OperaStoreOptions) {
    this.#dir = opts.dir;
    this.#counters = opts.counters;
    this.#userAgent = opts.userAgent;
    this.#now = opts.now ?? Date.now;
    this.#fetch = opts.fetch ?? ((input, init) => globalThis.fetch(input, init));
    this.#log = opts.log;
  }

  /** The frames of the last [OPERA_HISTORY_MS], oldest first, epoch ms. */
  async frames(): Promise<number[]> {
    const now = this.#now();
    const mine = this.#listing;
    if (mine !== undefined && now - mine.at < LISTING_TTL_S * 1000) return mine.frames;
    this.#listingInFlight ??= this.#list().finally(() => {
      this.#listingInFlight = undefined;
    });
    return this.#listingInFlight;
  }

  async #list(): Promise<number[]> {
    const now = this.#now();
    const shared = await this.#counters.get<{ at: number; frames: number[] }>(LISTING_KEY);
    if (shared !== undefined && now - shared.at < LISTING_TTL_S * 1000) {
      this.#listing = shared;
      return shared.frames;
    }
    if ((await this.#counters.get<boolean>(LISTING_FAIL_KEY)) === true) {
      throw new OperaUpstreamError('listing failed a moment ago');
    }
    const from = now - OPERA_HISTORY_MS;
    const hours: number[] = [];
    for (let h = from - (from % 3_600_000); h <= now; h += 3_600_000) hours.push(h);
    const found = new Set<number>();
    try {
      for (const hour of hours) {
        const prefix = `${dayPath(hour)}/OPERA/COMP/OPERA@${operaStamp(hour).slice(0, 11)}`;
        const url = `${OPERA_BUCKET}?list-type=2&prefix=${encodeURIComponent(prefix)}`;
        const res = await this.#get(url, LIST_TIMEOUT_MS);
        if (!res.ok) throw new OperaUpstreamError(`listing answered ${String(res.status)}`);
        for (const t of parseListing(await res.text())) {
          if (t >= from && t <= now) found.add(t);
        }
      }
    } catch (err) {
      await this.#counters.set(LISTING_FAIL_KEY, true, FAIL_TTL_S);
      throw err;
    }
    const frames = [...found].sort((a, b) => a - b);
    const listing = { at: now, frames };
    this.#listing = listing;
    await this.#counters.set(LISTING_KEY, listing, LISTING_TTL_S);
    return frames;
  }

  /** The PNG of the area `box` at frame `time`, `width` x `height`. */
  async image(time: number, box: MercatorBox, width: number, height: number): Promise<Buffer> {
    const key = `${String(time)}:${box.map((v) => v.toFixed(1)).join(',')}:${String(width)}x${String(height)}`;
    const cached = this.#images.get(key);
    if (cached !== undefined) {
      // Most recently used last.
      this.#images.delete(key);
      this.#images.set(key, cached);
      return cached;
    }
    const grid = await this.grid(time);
    const png = await encodeClassPng(width, height, classesOfArea(grid, box, width, height));
    // Two requests for the same image may have drawn it both; count it once.
    const earlier = this.#images.get(key);
    if (earlier !== undefined) this.#imageBytes -= earlier.length;
    this.#images.set(key, png);
    this.#imageBytes += png.length;
    for (const [k, v] of this.#images) {
      if (this.#imageBytes <= IMAGE_CACHE_BYTES) break;
      this.#images.delete(k);
      this.#imageBytes -= v.length;
    }
    return png;
  }

  /** The class grid of frame `time`: memory, disk, or the bucket once. */
  async grid(time: number): Promise<ClassGrid> {
    const held = this.#grids.get(time);
    if (held !== undefined) {
      this.#grids.delete(time);
      this.#grids.set(time, held);
      return held;
    }
    let pending = this.#inFlight.get(time);
    if (pending === undefined) {
      pending = this.#load(time).finally(() => this.#inFlight.delete(time));
      this.#inFlight.set(time, pending);
    }
    const grid = await pending;
    this.#grids.set(time, grid);
    while (this.#grids.size > GRIDS_IN_MEMORY) {
      const oldest = this.#grids.keys().next().value;
      if (oldest === undefined) break;
      this.#grids.delete(oldest);
    }
    return grid;
  }

  #file(time: number): string {
    return join(this.#dir, `${operaStamp(time)}.v${String(GRID_VERSION)}.grid`);
  }

  async #readFile(time: number): Promise<ClassGrid | undefined> {
    try {
      return await parseGrid(await readFile(this.#file(time)));
    } catch {
      return undefined;
    }
  }

  async #load(time: number): Promise<ClassGrid> {
    const onDisk = await this.#readFile(time);
    if (onDisk !== undefined) return onDisk;
    const failKey = `opera:fail:${String(time)}`;
    if ((await this.#counters.get<boolean>(failKey)) === true) {
      throw new OperaUpstreamError('frame failed a moment ago');
    }
    // One worker fetches; the others wait for its file, and fetch
    // themselves only if it never comes.
    const lock = await this.#counters.incr(`opera:lock:${String(time)}`, 1, {
      ttlIfNew: LOCK_TTL_S,
    });
    if (lock > 1) {
      const deadline = Date.now() + LOCK_WAIT_MS;
      while (Date.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, LOCK_POLL_MS));
        const theirs = await this.#readFile(time);
        if (theirs !== undefined) return theirs;
        if ((await this.#counters.get<boolean>(failKey)) === true) {
          throw new OperaUpstreamError('frame failed on another worker');
        }
      }
    }
    let grid: ClassGrid;
    try {
      grid = await this.#bounded(() => this.#fetchGrid(time));
    } catch (err) {
      // Not asked again for a while, by any worker.
      await this.#counters.set(failKey, true, FAIL_TTL_S);
      throw err;
    }
    await this.#write(time, grid);
    return grid;
  }

  /** Runs `job` once fewer than [MAX_FETCHES] are running in this worker. */
  async #bounded<T>(job: () => Promise<T>): Promise<T> {
    if (this.#fetching >= MAX_FETCHES) {
      // The slot is handed over by the job that ends, never taken twice.
      await new Promise<void>((resolve) => this.#queue.push(resolve));
    } else {
      this.#fetching += 1;
    }
    try {
      return await job();
    } finally {
      const next = this.#queue.shift();
      if (next === undefined) this.#fetching -= 1;
      else next();
    }
  }

  async #fetchGrid(time: number): Promise<ClassGrid> {
    const started = this.#now();
    const res = await this.#get(`${OPERA_BUCKET}/${operaKey(time)}`, FETCH_TIMEOUT_MS);
    if (!res.ok) throw new OperaUpstreamError(`frame answered ${String(res.status)}`);
    const body = new Uint8Array(await res.arrayBuffer());
    if (body.length === 0 || body.length > MAX_TIFF_BYTES) {
      throw new OperaUpstreamError('frame of unexpected size');
    }
    let grid: ClassGrid;
    try {
      grid = await decodeOperaTiff(body);
    } catch (err) {
      throw new OperaUpstreamError(`frame not readable: ${err instanceof Error ? err.message : String(err)}`);
    }
    this.#log?.info(
      { frame: operaStamp(time), bytes: body.length, ms: this.#now() - started },
      'opera frame fetched',
    );
    return grid;
  }

  async #write(time: number, grid: ClassGrid): Promise<void> {
    try {
      await mkdir(this.#dir, { recursive: true });
      const file = this.#file(time);
      const tmp = `${file}.${String(process.pid)}.tmp`;
      await writeFile(tmp, await serialiseGrid(grid));
      await rename(tmp, file);
      await this.prune();
    } catch (err) {
      // Served from memory all the same; the next worker fetches its own.
      this.#log?.warn({ err: String(err) }, 'opera grid not written');
    }
  }

  /** Deletes the grids older than [OPERA_KEEP_MS] and stray temporary files. */
  async prune(): Promise<void> {
    const cutoff = this.#now() - OPERA_KEEP_MS;
    let names: string[];
    try {
      names = await readdir(this.#dir);
    } catch {
      return;
    }
    for (const name of names) {
      const m = /^(\d{8}T\d{4})(?:\.v(\d+))?\.grid(\..+\.tmp)?$/.exec(name);
      if (m === null) continue;
      const s = m[1] ?? '';
      const t = Date.UTC(
        Number(s.slice(0, 4)),
        Number(s.slice(4, 6)) - 1,
        Number(s.slice(6, 8)),
        Number(s.slice(9, 11)),
        Number(s.slice(11, 13)),
      );
      // A grid of another version is never read again.
      const current = Number(m[2] ?? '1') === GRID_VERSION;
      if (current && t >= cutoff) continue;
      try {
        await unlink(join(this.#dir, name));
      } catch {
        // Another worker got there first.
      }
    }
  }

  async #get(url: string, timeoutMs: number): Promise<Response> {
    try {
      return await this.#fetch(url, {
        method: 'GET',
        headers: { 'user-agent': this.#userAgent },
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (err) {
      throw new OperaUpstreamError(`bucket unreachable: ${err instanceof Error ? err.name : 'error'}`);
    }
  }
}
