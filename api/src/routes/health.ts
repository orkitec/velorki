// SPDX-License-Identifier: AGPL-3.0-only
import type { FastifyInstance } from 'fastify';
import type { AppContext } from '../app.js';
import { llmConfigured } from '../config.js';

export type BrouterStatus = 'ok' | 'degraded' | 'unconfigured';

export interface HealthBody {
  status: 'ok';
  version: string;
  brouter: BrouterStatus;
  llm: 'configured' | 'unconfigured';
}

const BROUTER_CACHE_MS = 60_000;
const BROUTER_TIMEOUT_MS = 3_000;

/**
 * A short, cheap BRouter query (two points a kilometre apart near Zurich).
 * We only care that the routing engine answers, not about the result.
 */
const BROUTER_PROBE_PATH =
  '/brouter?lonlats=8.5,47.4|8.51,47.41&profile=trekking&alternativeidx=0&format=geojson';

export function registerHealthRoutes(app: FastifyInstance, ctx: AppContext): void {
  // Cached for 60 s so a monitoring loop cannot turn into a load test on BRouter.
  let cached: { value: BrouterStatus; at: number } | null = null;
  let inFlight: Promise<BrouterStatus> | null = null;

  async function probeBrouter(): Promise<BrouterStatus> {
    const base = ctx.config.BROUTER_URL;
    if (base === undefined) return 'unconfigured';
    try {
      const res = await fetch(`${base}${BROUTER_PROBE_PATH}`, {
        method: 'GET',
        signal: AbortSignal.timeout(BROUTER_TIMEOUT_MS),
      });
      // Drain the body so the connection can be reused / released.
      await res.text().catch(() => '');
      return res.ok ? 'ok' : 'degraded';
    } catch {
      return 'degraded';
    }
  }

  async function brouterStatus(): Promise<BrouterStatus> {
    const now = Date.now();
    if (cached !== null && now - cached.at < BROUTER_CACHE_MS) return cached.value;
    // Collapse concurrent probes into one request.
    inFlight ??= probeBrouter()
      .then((value) => {
        cached = { value, at: Date.now() };
        return value;
      })
      .finally(() => {
        inFlight = null;
      });
    return inFlight;
  }

  // Deliberately unauthenticated: Orkify's health check has no credentials.
  app.get('/health', async (_req, reply) => {
    const body: HealthBody = {
      status: 'ok',
      version: ctx.config.APP_VERSION,
      brouter: await brouterStatus(),
      llm: llmConfigured(ctx.config) ? 'configured' : 'unconfigured',
    };
    return reply.header('cache-control', 'no-store').send(body);
  });
}
