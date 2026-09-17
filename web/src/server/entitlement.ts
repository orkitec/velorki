// SPDX-License-Identifier: AGPL-3.0-only
import type { Config } from '@/config';
import { ApiError } from './errors';
import type { Counters } from './counters';

/** Positive answers are cached for 10 minutes, negative ones for 1. */
const POSITIVE_TTL_S = 600;
const NEGATIVE_TTL_S = 60;

const REVENUECAT_BASE = 'https://api.revenuecat.com/v1/subscribers';

export type FetchLike = typeof fetch;

interface RevenueCatEntitlement {
  expires_date?: string | null;
}

interface RevenueCatResponse {
  subscriber?: {
    entitlements?: Record<string, RevenueCatEntitlement | undefined>;
  };
}

/** True when the string holds a control character, a space, or DEL. */
function hasControlOrSpace(value: string): boolean {
  for (let i = 0; i < value.length; i += 1) {
    const code = value.charCodeAt(i);
    if (code <= 0x20 || code === 0x7f) return true;
  }
  return false;
}

/**
 * Extract the app_user_id from `Authorization: Bearer <id>`.
 * Anything missing or malformed is a 401 not_entitled; the two cases are
 * deliberately not distinguished for the caller.
 */
export function parseBearer(headers: Headers): string {
  const value = headers.get('authorization');
  if (value === null) {
    throw new ApiError('not_entitled', 'Missing Authorization header.');
  }
  const match = /^Bearer\s+(\S+)$/i.exec(value.trim());
  const id = match?.[1];
  // RevenueCat app user ids are opaque; bound the length and reject control
  // characters so the value is safe to put in a URL and in a cache key.
  if (id === undefined || id.length > 256 || hasControlOrSpace(id)) {
    throw new ApiError('not_entitled', 'Malformed Authorization header.');
  }
  return id;
}

/** Active when the entitlement exists and has no expiry, or expires in the future. */
function isActive(entitlement: RevenueCatEntitlement | undefined): boolean {
  if (entitlement === undefined) return false;
  const expires = entitlement.expires_date;
  if (expires === null || expires === undefined) return true;
  const ts = Date.parse(expires);
  if (Number.isNaN(ts)) return false;
  return ts > Date.now();
}

export class EntitlementService {
  readonly #config: Config;
  readonly #counters: Counters;
  readonly #fetch: FetchLike;

  constructor(config: Config, counters: Counters, fetchImpl?: FetchLike) {
    this.#config = config;
    this.#counters = counters;
    // Call through globalThis so tests can vi.stubGlobal('fetch', ...) after
    // the service has been constructed.
    this.#fetch = fetchImpl ?? ((input, init) => globalThis.fetch(input, init));
  }

  async isEntitled(
    appUserId: string,
    log?: { warn: (obj: object, msg: string) => void },
  ): Promise<boolean> {
    // Forks and local development run without a RevenueCat account.
    if (this.#config.REVENUECAT_MODE === 'stub') return true;

    if (!this.#config.REVENUECAT_SECRET_KEY) {
      throw new ApiError('unavailable', 'Entitlement checking is not configured on this server.');
    }

    const cacheKey = `ent:${this.#config.REVENUECAT_ENTITLEMENT}:${appUserId}`;
    const cached = await this.#counters.get<boolean>(cacheKey);
    if (cached !== undefined) return cached;

    const url = `${REVENUECAT_BASE}/${encodeURIComponent(appUserId)}`;
    let res: Response;
    try {
      res = await this.#fetch(url, {
        method: 'GET',
        headers: {
          authorization: `Bearer ${this.#config.REVENUECAT_SECRET_KEY}`,
          accept: 'application/json',
        },
        signal: AbortSignal.timeout(5_000),
      });
    } catch (cause) {
      log?.warn({ err: String(cause) }, 'revenuecat request failed');
      throw new ApiError('upstream_error', 'Could not reach the entitlement service.');
    }

    if (res.status >= 500) {
      // Upstream trouble must not be cached as "not entitled".
      log?.warn({ status: res.status }, 'revenuecat upstream error');
      throw new ApiError('upstream_error', 'The entitlement service is unavailable.');
    }

    if (!res.ok) {
      // 4xx: unknown subscriber or rejected key -> not entitled, cached briefly.
      await this.#counters.set(cacheKey, false, NEGATIVE_TTL_S);
      return false;
    }

    let body: RevenueCatResponse;
    try {
      body = (await res.json()) as RevenueCatResponse;
    } catch {
      throw new ApiError('upstream_error', 'The entitlement service returned an invalid response.');
    }

    const entitlement = body.subscriber?.entitlements?.[this.#config.REVENUECAT_ENTITLEMENT];
    const entitled = isActive(entitlement);
    await this.#counters.set(cacheKey, entitled, entitled ? POSITIVE_TTL_S : NEGATIVE_TTL_S);
    return entitled;
  }
}

/**
 * The gate every authenticated route runs first. Returns the app_user_id so
 * the handler can use it as a rate-limit key.
 */
export async function requireEntitlement(
  service: EntitlementService,
  headers: Headers,
  log?: { warn: (obj: object, msg: string) => void },
): Promise<string> {
  const id = parseBearer(headers);
  const entitled = await service.isEntitled(id, log);
  if (!entitled) {
    throw new ApiError('not_entitled', 'An active Velorki subscription is required.');
  }
  return id;
}
