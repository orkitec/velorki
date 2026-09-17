// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import { MemoryCounters } from '@/server/counters';
import { LIMITS, consume, windowKey } from '@/server/ratelimit';

describe('MemoryCounters', () => {
  it('applies ttlIfNew only when the key is created', async () => {
    let now = 1_000_000;
    const c = new MemoryCounters({ now: () => now });

    expect(await c.incr('k', 1, { ttlIfNew: 60 })).toBe(1);
    now += 30_000;
    // A later increment must not slide the window.
    expect(await c.incr('k', 1, { ttlIfNew: 60 })).toBe(2);
    now += 29_999;
    expect(await c.get<number>('k')).toBe(2);
    now += 2;
    expect(await c.get<number>('k')).toBeUndefined();
    // The key is gone, so the next incr starts a new window.
    expect(await c.incr('k', 1, { ttlIfNew: 60 })).toBe(1);
  });

  it('stores values with a ttl and forgets them after it', async () => {
    let now = 0;
    const c = new MemoryCounters({ now: () => now });
    await c.set('flag', true, 10);
    expect(await c.get<boolean>('flag')).toBe(true);
    now = 10_001;
    expect(await c.get<boolean>('flag')).toBeUndefined();
  });

  it('keeps a value without a ttl', async () => {
    let now = 0;
    const c = new MemoryCounters({ now: () => now });
    await c.set('forever', 'x');
    now = 10 ** 12;
    expect(await c.get<string>('forever')).toBe('x');
  });
});

describe('fixed-window rate limits', () => {
  it('keys a window by name, key and window start', () => {
    expect(windowKey(LIMITS.stravaTokenPerMin, '1.2.3.4', 1_800_090)).toBe(
      'rl:strava_token_min:1.2.3.4:1800060',
    );
  });

  it('denies the 11th call in a minute whichever consumer makes it', async () => {
    // Two MemoryCounters over one map: two cluster workers on one cache.
    const shared = new Map();
    let now = 1_700_000_000_000;
    const workerA = new MemoryCounters({ store: shared, now: () => now });
    const workerB = new MemoryCounters({ store: shared, now: () => now });
    const limits = [LIMITS.stravaTokenPerMin];

    for (let i = 0; i < 10; i += 1) {
      const counters = i % 2 === 0 ? workerA : workerB;
      const result = await consume(counters, 'ip', limits, now);
      expect(result.allowed, `call ${String(i)}`).toBe(true);
    }

    const denied = await consume(workerB, 'ip', limits, now);
    expect(denied.allowed).toBe(false);
    expect(denied.limit?.name).toBe('strava_token_min');
    expect(denied.retryAfterS).toBeGreaterThan(0);
    expect(denied.retryAfterS).toBeLessThanOrEqual(60);

    // The other worker agrees.
    expect((await consume(workerA, 'ip', limits, now)).allowed).toBe(false);

    // The next window starts fresh.
    now += 60_000;
    expect((await consume(workerA, 'ip', limits, now)).allowed).toBe(true);
  });

  it('reports the seconds left in the window, at least one', async () => {
    const counters = new MemoryCounters();
    const spec = { name: 't', limit: 1, windowS: 60 };
    // 59.5 s into the window: half a second left, reported as 1.
    const now = 1_700_000_040_000 - 1_700_000_040_000 + 59_500;
    await consume(counters, 'k', [spec], now);
    const denied = await consume(counters, 'k', [spec], now);
    expect(denied.allowed).toBe(false);
    expect(denied.retryAfterS).toBe(1);
  });

  it('keeps different keys apart', async () => {
    const counters = new MemoryCounters();
    const spec = { name: 't', limit: 1, windowS: 60 };
    expect((await consume(counters, 'a', [spec])).allowed).toBe(true);
    expect((await consume(counters, 'b', [spec])).allowed).toBe(true);
    expect((await consume(counters, 'a', [spec])).allowed).toBe(false);
  });

  it('reports the longest wait when several limits are exhausted', async () => {
    const counters = new MemoryCounters();
    const perMinute = { name: 'm', limit: 1, windowS: 60 };
    const perDay = { name: 'd', limit: 1, windowS: 86_400 };
    const now = 0;

    expect((await consume(counters, 'k', [perMinute, perDay], now)).allowed).toBe(true);
    const denied = await consume(counters, 'k', [perMinute, perDay], now);
    expect(denied.allowed).toBe(false);
    expect(denied.limit?.name).toBe('d');
    expect(denied.retryAfterS).toBe(86_400);
  });

  it('exposes the daily share limit as 30 per day', () => {
    expect(LIMITS.sharePerDay).toEqual({ name: 'share_day', limit: 30, windowS: 86_400 });
  });

  it('keeps every relay limit number unchanged', () => {
    expect(LIMITS).toEqual({
      stravaTokenPerMin: { name: 'strava_token_min', limit: 10, windowS: 60 },
      stravaTokenPerDay: { name: 'strava_token_day', limit: 60, windowS: 86_400 },
      stravaRefreshPerHour: { name: 'strava_refresh_hour', limit: 30, windowS: 3_600 },
      rwgpsTokenPerMin: { name: 'rwgps_token_min', limit: 10, windowS: 60 },
      rwgpsTokenPerDay: { name: 'rwgps_token_day', limit: 60, windowS: 86_400 },
      aiPlanPerHour: { name: 'ai_plan_hour', limit: 20, windowS: 3_600 },
      aiPlanPerDay: { name: 'ai_plan_day', limit: 100, windowS: 86_400 },
      aiPlanPerIpHour: { name: 'ai_plan_ip_hour', limit: 60, windowS: 3_600 },
      sharePerDay: { name: 'share_day', limit: 30, windowS: 86_400 },
    });
  });
});
