// SPDX-License-Identifier: AGPL-3.0-only
import { llmConfigured } from '@/config';
import { json, withApi } from '@/server/api';
import { getConfig } from '@/server/singletons';

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

/**
 * Module-level, so the 60 s cache is shared by every request this worker
 * answers: a monitoring loop must not turn into a load test on BRouter.
 */
let cached: { value: BrouterStatus; at: number } | null = null;
let inFlight: Promise<BrouterStatus> | null = null;

async function probeBrouter(base: string | undefined): Promise<BrouterStatus> {
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

async function brouterStatus(base: string | undefined): Promise<BrouterStatus> {
  const now = Date.now();
  if (cached !== null && now - cached.at < BROUTER_CACHE_MS) return cached.value;
  // Collapse concurrent probes into one request.
  inFlight ??= probeBrouter(base)
    .then((value) => {
      cached = { value, at: Date.now() };
      return value;
    })
    .finally(() => {
      inFlight = null;
    });
  return inFlight;
}

/** Tests only: forget the probe result between cases. */
export function resetBrouterCache(): void {
  cached = null;
  inFlight = null;
}

async function healthResponse(): Promise<Response> {
  const config = getConfig();
  const body: HealthBody = {
    status: 'ok',
    version: config.APP_VERSION,
    brouter: await brouterStatus(config.BROUTER_URL),
    llm: llmConfigured(config) ? 'configured' : 'unconfigured',
  };
  return json(body, 200, { 'cache-control': 'no-store' });
}

// Deliberately unauthenticated: Orkify's health check has no credentials.
export const GET = withApi(async () => healthResponse());
export const HEAD = withApi(async () => healthResponse());
