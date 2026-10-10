// SPDX-License-Identifier: AGPL-3.0-only
import type { WeatherContext } from './types';

/** Per upstream call. A slow provider is a failed one: the cell falls back. */
export const UPSTREAM_TIMEOUT_MS = 6_000;

/**
 * A failed upstream call. The message is the provider and the status only:
 * the URL carries the cell's coordinates, which must not reach a log.
 */
export class UpstreamError extends Error {
  readonly provider: string;
  readonly status: number | 'timeout' | 'network' | 'parse' | 'no_data';

  constructor(provider: string, status: UpstreamError['status']) {
    super(`${provider}: ${String(status)}`);
    this.name = 'UpstreamError';
    this.provider = provider;
    this.status = status;
  }
}

export function userAgent(version: string, baseUrl: string, contact: string | undefined): string {
  return `Velorki/${version} (+${baseUrl}${contact === undefined ? '' : `; ${contact}`})`;
}

/**
 * GET `url` for `provider` with our User-Agent and the per-call timeout.
 * Network failures and timeouts become `UpstreamError`; any status comes back
 * as the Response, since a 304 or a 404 can be an answer.
 */
export async function upstreamGet(
  ctx: WeatherContext,
  provider: string,
  url: string,
  signal: AbortSignal,
  headers: Record<string, string> = {},
): Promise<Response> {
  ctx.stats.upstream[provider] = (ctx.stats.upstream[provider] ?? 0) + 1;
  const timeout = AbortSignal.timeout(UPSTREAM_TIMEOUT_MS);
  try {
    return await fetch(url, {
      method: 'GET',
      headers: { 'user-agent': ctx.userAgent, accept: 'application/json', ...headers },
      signal: AbortSignal.any([signal, timeout]),
    });
  } catch {
    throw new UpstreamError(provider, timeout.aborted ? 'timeout' : 'network');
  }
}

/** The body as JSON, or a `parse` failure. */
export async function readJson(provider: string, res: Response): Promise<unknown> {
  try {
    return (await res.json()) as unknown;
  } catch {
    throw new UpstreamError(provider, 'parse');
  }
}

/**
 * One load per key per worker: concurrent requests for the same forecast,
 * and two cells of one request that round to the same point, wait for the
 * first instead of calling the provider again. The first caller's signal
 * governs the shared load.
 */
const inflight = new Map<string, Promise<unknown>>();

export function once<T>(key: string, load: () => Promise<T>): Promise<T> {
  const pending = inflight.get(key);
  if (pending !== undefined) return pending as Promise<T>;
  const promise = load().finally(() => inflight.delete(key));
  inflight.set(key, promise);
  return promise;
}

/**
 * Read `key` from the shared counters, or load it once and keep it `ttlS`
 * seconds (a function when the answer decides). The counters are the
 * cross-worker cache: both workers see what either fetched.
 */
export async function cached<T>(
  ctx: WeatherContext,
  key: string,
  ttlS: number | ((value: T) => number),
  load: () => Promise<T>,
): Promise<T> {
  const hit = await ctx.counters.get<T>(key);
  if (hit !== undefined) {
    ctx.stats.hits += 1;
    return hit;
  }
  ctx.stats.misses += 1;
  return once(key, async () => {
    const value = await load();
    await ctx.counters.set(key, value, typeof ttlS === 'number' ? ttlS : ttlS(value));
    return value;
  });
}

/** Snap a coordinate to a grid of `step` degrees, printed without float noise. */
export function snap(value: number, step: number): number {
  return Number((Math.round(value / step) * step).toFixed(4));
}
