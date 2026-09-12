// SPDX-License-Identifier: AGPL-3.0-only
import type { FastifyReply, FastifyRequest } from 'fastify';
import type { Config } from '../config.js';
import { ApiError } from './errors.js';
import { LruCache } from '../util/lru.js';
import { firstHeaderValue } from './requestid.js';

declare module 'fastify' {
  interface FastifyRequest {
    /** RevenueCat app_user_id of the caller, set by the entitlement preHandler. */
    appUserId: string | null;
  }
}

const POSITIVE_TTL_MS = 10 * 60 * 1000;
const NEGATIVE_TTL_MS = 60 * 1000;
const CACHE_MAX_ENTRIES = 10_000;

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

/**
 * Extract the app_user_id from `Authorization: Bearer <id>`.
 * Anything missing or malformed is a 401 not_entitled; the two cases are
 * deliberately not distinguished for the caller.
 */
export function parseBearer(req: FastifyRequest): string {
  const value = firstHeaderValue(req.headers.authorization);
  if (value === undefined) {
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

/** True when the string holds a control character, a space, or DEL. */
function hasControlOrSpace(value: string): boolean {
  for (let i = 0; i < value.length; i += 1) {
    const code = value.charCodeAt(i);
    if (code <= 0x20 || code === 0x7f) return true;
  }
  return false;
}

export class EntitlementService {
  readonly #config: Config;
  readonly #fetch: FetchLike;
  readonly #cache: LruCache<boolean>;

  constructor(config: Config, fetchImpl?: FetchLike) {
    this.#config = config;
    // Call through globalThis so tests can vi.stubGlobal('fetch', ...) after
    // the service has been constructed.
    this.#fetch = fetchImpl ?? ((input, init) => globalThis.fetch(input, init));
    this.#cache = new LruCache<boolean>(CACHE_MAX_ENTRIES);
  }

  /** Exposed for tests that need a clean slate. */
  clearCache(): void {
    this.#cache.clear();
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

    const cached = this.#cache.get(appUserId);
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
      this.#cache.set(appUserId, false, NEGATIVE_TTL_MS);
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
    this.#cache.set(appUserId, entitled, entitled ? POSITIVE_TTL_MS : NEGATIVE_TTL_MS);
    return entitled;
  }
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

/** preHandler for every authenticated route. Sets `req.appUserId` on success. */
export function requireEntitlement(service: EntitlementService) {
  return async function entitlementPreHandler(
    req: FastifyRequest,
    _reply: FastifyReply,
  ): Promise<void> {
    const id = parseBearer(req);
    const entitled = await service.isEntitled(id, req.log);
    if (!entitled) {
      throw new ApiError('not_entitled', 'An active Velorki subscription is required.');
    }
    req.appUserId = id;
  };
}

/** The entitlement preHandler guarantees this is set; helper keeps handlers tidy. */
export function appUserId(req: FastifyRequest): string {
  const id = req.appUserId;
  if (id === null) throw new ApiError('not_entitled', 'Not authenticated.');
  return id;
}
