// SPDX-License-Identifier: AGPL-3.0-only
import { llmConfigured, rwgpsConfigured, stravaConfigured, type Config } from '@/config';
import { json, withApi } from '@/server/api';
import { getConfig } from '@/server/singletons';

export type BrouterStatus = 'ok' | 'degraded' | 'unconfigured';

type Configured = 'configured' | 'unconfigured';

export interface HealthBody {
  status: 'ok';
  version: string;
  brouter: BrouterStatus;
  llm: Configured;
  /** The model id when an LLM is configured - not a secret, and the first thing to check. */
  llm_model: string | null;
  strava: Configured;
  rwgps: Configured;
  /**
   * `live` verifies purchases against RevenueCat; `stub` lets everyone through
   * (development only); `unconfigured` is live mode without a secret key, which
   * refuses every Plus request.
   */
  entitlement: 'live' | 'stub' | 'unconfigured';
  /** Needed by every OAuth token exchange and pass-through call. */
  token_wrap: Configured;
}

/**
 * Whether each integration has what it needs - never the values. Dashboard
 * secrets are write-only, so this and the boot log's fingerprints are how a
 * deploy is checked from outside.
 */
function entitlementStatus(config: Config): HealthBody['entitlement'] {
  if (config.REVENUECAT_MODE === 'stub') return 'stub';
  return config.REVENUECAT_SECRET_KEY ? 'live' : 'unconfigured';
}

const flag = (on: boolean): Configured => (on ? 'configured' : 'unconfigured');

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
    llm: flag(llmConfigured(config)),
    llm_model: llmConfigured(config) ? (config.LLM_MODEL ?? null) : null,
    strava: flag(stravaConfigured(config)),
    rwgps: flag(rwgpsConfigured(config)),
    entitlement: entitlementStatus(config),
    token_wrap: flag(config.TOKEN_WRAP_KEYS !== undefined),
  };
  return json(body, 200, { 'cache-control': 'no-store' });
}

// Deliberately unauthenticated: Orkify's health check has no credentials.
export const GET = withApi(async () => healthResponse());
export const HEAD = withApi(async () => healthResponse());
