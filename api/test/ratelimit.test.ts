// SPDX-License-Identifier: AGPL-3.0-only
import { afterEach, describe, expect, it, vi } from 'vitest';
import { LIMITS, RateLimiter } from '../src/util/tokenbucket.js';
import { LruCache } from '../src/util/lru.js';
import {
  AUTH,
  errOf,
  testApp,
} from './helpers.js';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('token bucket', () => {
  it('allows the burst and then refuses', () => {
    const now = 1_000_000;
    const limiter = new RateLimiter(() => now);
    const spec = { name: 't', limit: 3, windowS: 60 };

    for (let i = 0; i < 3; i += 1) {
      expect(limiter.consume('k', [spec]).allowed, `call ${String(i)}`).toBe(true);
    }
    const denied = limiter.consume('k', [spec]);
    expect(denied.allowed).toBe(false);
    expect(denied.retryAfterS).toBeGreaterThan(0);
    expect(denied.retryAfterS).toBeLessThanOrEqual(20);
  });

  it('refills over time', () => {
    let now = 0;
    const limiter = new RateLimiter(() => now);
    const spec = { name: 't', limit: 2, windowS: 60 };

    expect(limiter.consume('k', [spec]).allowed).toBe(true);
    expect(limiter.consume('k', [spec]).allowed).toBe(true);
    expect(limiter.consume('k', [spec]).allowed).toBe(false);

    now += 60_000;
    expect(limiter.consume('k', [spec]).allowed).toBe(true);
    expect(limiter.consume('k', [spec]).allowed).toBe(true);
    expect(limiter.consume('k', [spec]).allowed).toBe(false);
  });

  it('keeps different keys apart', () => {
    const limiter = new RateLimiter();
    const spec = { name: 't', limit: 1, windowS: 60 };
    expect(limiter.consume('a', [spec]).allowed).toBe(true);
    expect(limiter.consume('b', [spec]).allowed).toBe(true);
    expect(limiter.consume('a', [spec]).allowed).toBe(false);
  });

  it('consumes nothing when one of several limits is exhausted', () => {
    const now = 0;
    const limiter = new RateLimiter(() => now);
    const perMinute = { name: 'm', limit: 10, windowS: 60 };
    const perDay = { name: 'd', limit: 2, windowS: 86_400 };

    expect(limiter.consume('k', [perMinute, perDay]).allowed).toBe(true);
    expect(limiter.consume('k', [perMinute, perDay]).allowed).toBe(true);

    const denied = limiter.consume('k', [perMinute, perDay]);
    expect(denied.allowed).toBe(false);
    expect(denied.limit?.name).toBe('d');
    // The per-minute bucket must still have 8 tokens, not 7.
    expect(limiter.consume('k', [perMinute]).allowed).toBe(true);
  });

  it('exposes the daily share limit as 30 per day', () => {
    expect(LIMITS.sharePerDay).toEqual({ name: 'share_day', limit: 30, windowS: 86_400 });
  });
});

describe('LRU cache', () => {
  it('evicts the least recently used entry past the maximum', () => {
    const cache = new LruCache<number>(2);
    cache.set('a', 1, 10_000);
    cache.set('b', 2, 10_000);
    cache.get('a'); // 'a' is now the most recent
    cache.set('c', 3, 10_000);

    expect(cache.get('b')).toBeUndefined();
    expect(cache.get('a')).toBe(1);
    expect(cache.get('c')).toBe(3);
    expect(cache.size).toBe(2);
  });

  it('expires entries by TTL', () => {
    let now = 0;
    const cache = new LruCache<string>(10, () => now);
    cache.set('k', 'v', 1_000);
    expect(cache.get('k')).toBe('v');
    now = 1_001;
    expect(cache.get('k')).toBeUndefined();
  });
});

describe('HTTP rate limiting', () => {
  it('returns 429 with retry_after_s and a Retry-After header', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response(JSON.stringify({ access_token: 'a' }), { status: 200 })),
    );

    const app = testApp({
      env: {
        STRAVA_CLIENT_ID: '1',
        STRAVA_CLIENT_SECRET: 's',
        OAUTH_REDIRECT_ALLOWLIST: 'velorki://oauth/strava',
      },
    });
    const payload = { code: 'c', redirect_uri: 'velorki://oauth/strava' };
    const call = () =>
      app.inject({ method: 'POST', url: '/oauth/strava/token', headers: AUTH, payload });

    // The per-minute limit for the strava token route is 10.
    for (let i = 0; i < 10; i += 1) {
      expect((await call()).statusCode, `call ${String(i)}`).toBe(200);
    }

    const limited = await call();
    expect(limited.statusCode).toBe(429);
    const body = errOf(limited);
    expect(body.code).toBe('rate_limited');
    expect(body.retry_after_s).toBeGreaterThan(0);
    expect(limited.headers['retry-after']).toBe(String(body.retry_after_s));

    await app.close();
  });
});
