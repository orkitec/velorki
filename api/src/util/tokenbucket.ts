// SPDX-License-Identifier: AGPL-3.0-only

/**
 * In-memory token buckets. This service is deployed as a single Node process
 * (Orkify runs one instance), so process-local state is the whole story; there
 * is deliberately no Redis dependency.
 *
 * A limit of "10 per minute" is a bucket of capacity 10 that refills at
 * 10/60 tokens per second, i.e. it allows a burst of 10 and then a steady
 * trickle. Denied requests get the number of seconds until one token is back.
 */

export interface LimitSpec {
  /** Human-readable name, used in logs and in the 429 message. */
  readonly name: string;
  /** Burst size / number of requests allowed per window. */
  readonly limit: number;
  /** Window length in seconds (60 = per minute, 3600 = per hour, 86400 = per day). */
  readonly windowS: number;
}

interface Bucket {
  tokens: number;
  updatedAt: number;
}

export interface RateLimitResult {
  allowed: boolean;
  /** Seconds until the next token is available; only meaningful when denied. */
  retryAfterS: number;
  /** Which limit rejected the request. */
  limit?: LimitSpec;
}

export class RateLimiter {
  readonly #buckets = new Map<string, Bucket>();
  readonly #now: () => number;
  readonly #maxKeys: number;

  constructor(now: () => number = Date.now, maxKeys = 50_000) {
    this.#now = now;
    this.#maxKeys = maxKeys;
  }

  /**
   * Try to consume one token from every given limit for `key`.
   * All-or-nothing: if any limit is exhausted, nothing is consumed.
   */
  consume(key: string, limits: readonly LimitSpec[]): RateLimitResult {
    const now = this.#now();

    // First pass: refill and check, without mutating token counts.
    let worst: { retryAfterS: number; limit: LimitSpec } | undefined;
    const prepared: { id: string; bucket: Bucket; spec: LimitSpec }[] = [];

    for (const spec of limits) {
      const id = `${spec.name}:${key}`;
      const ratePerMs = spec.limit / (spec.windowS * 1000);
      let bucket = this.#buckets.get(id);
      if (bucket === undefined) {
        bucket = { tokens: spec.limit, updatedAt: now };
      } else {
        const refill = (now - bucket.updatedAt) * ratePerMs;
        bucket = {
          tokens: Math.min(spec.limit, bucket.tokens + refill),
          updatedAt: now,
        };
      }
      prepared.push({ id, bucket, spec });

      if (bucket.tokens < 1) {
        const secondsToOneToken = Math.ceil((1 - bucket.tokens) / (ratePerMs * 1000));
        const retryAfterS = Math.max(1, secondsToOneToken);
        if (worst === undefined || retryAfterS > worst.retryAfterS) {
          worst = { retryAfterS, limit: spec };
        }
      }
    }

    if (worst !== undefined) {
      // Still persist the refilled state so the clock keeps moving.
      for (const p of prepared) this.#store(p.id, p.bucket);
      return { allowed: false, retryAfterS: worst.retryAfterS, limit: worst.limit };
    }

    for (const p of prepared) {
      this.#store(p.id, { tokens: p.bucket.tokens - 1, updatedAt: p.bucket.updatedAt });
    }
    return { allowed: true, retryAfterS: 0 };
  }

  #store(id: string, bucket: Bucket): void {
    // Bound memory: drop the oldest inserted key when the map grows too big.
    // A full bucket is indistinguishable from a missing one, so evicting is safe.
    if (!this.#buckets.has(id) && this.#buckets.size >= this.#maxKeys) {
      const oldest = this.#buckets.keys().next();
      if (oldest.done !== true) this.#buckets.delete(oldest.value);
    }
    this.#buckets.set(id, bucket);
  }

  reset(): void {
    this.#buckets.clear();
  }
}

/** Common limit definitions used by the routes. */
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
} as const satisfies Record<string, LimitSpec>;
