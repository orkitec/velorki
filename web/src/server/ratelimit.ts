// SPDX-License-Identifier: AGPL-3.0-only
import { ApiError } from './errors';
import type { Counters } from './counters';

/**
 * Fixed-window rate limits on `Counters`.
 *
 * The Fastify relay used per-process token buckets, which cannot be shared by
 * two cluster workers. The numbers are unchanged; the shape is not: a window is
 * a counter key that expires, so a limit of "10 per minute" allows 10 requests
 * inside one wall-clock minute with no carried-over burst credit. `Retry-After`
 * is the time left in the window that rejected the request.
 */

export interface LimitSpec {
  /** Human-readable name, used in logs and in the counter key. */
  readonly name: string;
  /** Number of requests allowed per window. */
  readonly limit: number;
  /** Window length in seconds (60 = per minute, 3600 = per hour, 86400 = per day). */
  readonly windowS: number;
}

export interface RateLimitResult {
  allowed: boolean;
  /** Seconds until the window rolls over; only meaningful when denied. */
  retryAfterS: number;
  /** Which limit rejected the request. */
  limit?: LimitSpec;
}

/** Common limit definitions used by the routes. Same numbers as the relay's. */
export const LIMITS = {
  stravaTokenPerMin: { name: 'strava_token_min', limit: 10, windowS: 60 },
  stravaTokenPerDay: { name: 'strava_token_day', limit: 60, windowS: 86_400 },
  stravaRefreshPerHour: { name: 'strava_refresh_hour', limit: 30, windowS: 3_600 },
  rwgpsTokenPerMin: { name: 'rwgps_token_min', limit: 10, windowS: 60 },
  rwgpsTokenPerDay: { name: 'rwgps_token_day', limit: 60, windowS: 86_400 },
  aiPlanPerHour: { name: 'ai_plan_hour', limit: 20, windowS: 3_600 },
  aiPlanPerDay: { name: 'ai_plan_day', limit: 100, windowS: 86_400 },
  aiPlanPerIpHour: { name: 'ai_plan_ip_hour', limit: 60, windowS: 3_600 },
  sharePerDay: { name: 'share_day', limit: 30, windowS: 86_400 },
  /**
   * Charged before the body is read, so an unauthenticated caller cannot keep
   * a worker buffering megabytes; the per-user daily limit is the real one.
   */
  sharePerIpHour: { name: 'share_ip_hour', limit: 60, windowS: 3_600 },
} as const satisfies Record<string, LimitSpec>;

/** The counter key of one window. Exported so tests can assert the shape. */
export function windowKey(spec: LimitSpec, key: string, nowS: number): string {
  const windowStart = Math.floor(nowS / spec.windowS) * spec.windowS;
  return `rl:${spec.name}:${key}:${String(windowStart)}`;
}

export async function consume(
  counters: Counters,
  key: string,
  limits: readonly LimitSpec[],
  now: number = Date.now(),
): Promise<RateLimitResult> {
  const nowS = Math.floor(now / 1000);
  let worst: { retryAfterS: number; limit: LimitSpec } | undefined;

  for (const spec of limits) {
    const windowStart = Math.floor(nowS / spec.windowS) * spec.windowS;
    const count = await counters.incr(`rl:${spec.name}:${key}:${String(windowStart)}`, 1, {
      ttlIfNew: spec.windowS,
    });
    if (count > spec.limit) {
      const retryAfterS = Math.max(1, windowStart + spec.windowS - nowS);
      if (worst === undefined || retryAfterS > worst.retryAfterS) {
        worst = { retryAfterS, limit: spec };
      }
    }
  }

  if (worst !== undefined) {
    return { allowed: false, retryAfterS: worst.retryAfterS, limit: worst.limit };
  }
  return { allowed: true, retryAfterS: 0 };
}

/** Consume one request from every limit or throw the 429 the contract defines. */
export async function enforce(
  counters: Counters,
  key: string,
  limits: readonly LimitSpec[],
  log?: { info: (obj: object, msg: string) => void },
): Promise<void> {
  const result = await consume(counters, key, limits);
  if (!result.allowed) {
    log?.info({ limit: result.limit?.name }, 'rate limited');
    throw new ApiError('rate_limited', 'Too many requests. Please slow down.', {
      retryAfterS: result.retryAfterS,
    });
  }
}
