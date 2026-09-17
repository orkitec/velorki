// SPDX-License-Identifier: AGPL-3.0-only
import { afterEach, describe, expect, it, vi } from 'vitest';
import { POST as stravaToken } from '@/app/(api)/oauth/strava/token/route';
import { EntitlementService, parseBearer } from '@/server/entitlement';
import { ApiError } from '@/server/errors';
import { MemoryCounters } from '@/server/counters';
import { errOf, fetchCall, jsonRequest, revenueCatResponse, testConfig, withEnv } from './helpers';

afterEach(() => {
  vi.unstubAllGlobals();
});

const liveEnv = {
  REVENUECAT_MODE: 'live',
  REVENUECAT_SECRET_KEY: 'sk_test_do_not_log',
  REVENUECAT_ENTITLEMENT: 'plus',
  STRAVA_CLIENT_ID: '1234',
  STRAVA_CLIENT_SECRET: 'strava-secret',
  OAUTH_REDIRECT_ALLOWLIST: 'velorki://oauth/strava',
};

function callStrava(auth?: string): Promise<Response> {
  return stravaToken(
    jsonRequest(
      'https://api.velorki.com/oauth/strava/token',
      { code: 'abc', redirect_uri: 'velorki://oauth/strava' },
      auth === undefined ? {} : { authorization: auth },
    ),
  );
}

function service(env: Record<string, string>): EntitlementService {
  return new EntitlementService(testConfig(env), new MemoryCounters());
}

describe('entitlement: header handling', () => {
  it('rejects a missing Authorization header with 401 not_entitled', async () => {
    await withEnv(liveEnv, async () => {
      const res = await callStrava();
      expect(res.status).toBe(401);
      expect((await errOf(res)).code).toBe('not_entitled');
    });
  });

  it('rejects a malformed Authorization header', async () => {
    await withEnv(liveEnv, async () => {
      for (const header of ['Basic abc', 'Bearer', 'Bearer  ', 'token-without-scheme']) {
        const res = await callStrava(header);
        expect(res.status, header).toBe(401);
        expect((await errOf(res)).code).toBe('not_entitled');
      }
    });
  });

  it('bounds the app_user_id length and charset', () => {
    expect(parseBearer(new Headers({ authorization: 'Bearer abc' }))).toBe('abc');
    expect(() => parseBearer(new Headers({ authorization: `Bearer ${'x'.repeat(257)}` }))).toThrow(
      ApiError,
    );
    expect(() => parseBearer(new Headers())).toThrow(ApiError);
  });
});

describe('entitlement: stub mode', () => {
  it('treats everyone as entitled without calling RevenueCat', async () => {
    const fetchMock = vi.fn(async () => new Response('{}', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await expect(service({ REVENUECAT_MODE: 'stub' }).isEntitled('anyone')).resolves.toBe(true);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe('entitlement: live mode', () => {
  it('accepts an entitlement with a null expiry', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => revenueCatResponse('plus', null)));
    await expect(service(liveEnv).isEntitled('user-1')).resolves.toBe(true);
  });

  it('accepts an entitlement expiring in the future', async () => {
    const future = new Date(Date.now() + 86_400_000).toISOString();
    vi.stubGlobal('fetch', vi.fn(async () => revenueCatResponse('plus', future)));
    await expect(service(liveEnv).isEntitled('user-1')).resolves.toBe(true);
  });

  it('rejects an expired entitlement and a missing one', async () => {
    const past = new Date(Date.now() - 1000).toISOString();
    vi.stubGlobal('fetch', vi.fn(async () => revenueCatResponse('plus', past)));
    await expect(service(liveEnv).isEntitled('u')).resolves.toBe(false);

    vi.stubGlobal('fetch', vi.fn(async () => revenueCatResponse('plus', undefined)));
    await expect(service(liveEnv).isEntitled('u')).resolves.toBe(false);
  });

  it('sends the secret key to RevenueCat and only to RevenueCat', async () => {
    const fetchMock = vi.fn(async () => revenueCatResponse('plus', null));
    vi.stubGlobal('fetch', fetchMock);

    await service(liveEnv).isEntitled('user with/slash');

    const { url, init } = fetchCall(fetchMock);
    expect(url).toBe('https://api.revenuecat.com/v1/subscribers/user%20with%2Fslash');
    expect((init.headers as Record<string, string>).authorization).toBe('Bearer sk_test_do_not_log');
  });

  it('caches the positive answer instead of asking again', async () => {
    const fetchMock = vi.fn(async () => revenueCatResponse('plus', null));
    vi.stubGlobal('fetch', fetchMock);

    const svc = service(liveEnv);
    await svc.isEntitled('same-user');
    await svc.isEntitled('same-user');
    await svc.isEntitled('same-user');
    expect(fetchMock).toHaveBeenCalledTimes(1);

    // A different user is a different cache entry.
    await svc.isEntitled('other-user');
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('caches the negative answer too', async () => {
    const fetchMock = vi.fn(async () => revenueCatResponse('plus', undefined));
    vi.stubGlobal('fetch', fetchMock);

    const svc = service(liveEnv);
    await svc.isEntitled('freeloader');
    await svc.isEntitled('freeloader');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('expires the positive answer after 600 s and the negative after 60 s', async () => {
    let now = 1_000_000;
    const counters = new MemoryCounters({ now: () => now });
    const config = testConfig(liveEnv);

    const positive = vi.fn(async () => revenueCatResponse('plus', null));
    vi.stubGlobal('fetch', positive);
    const yes = new EntitlementService(config, counters);
    await yes.isEntitled('a');
    now += 599_000;
    await yes.isEntitled('a');
    expect(positive).toHaveBeenCalledTimes(1);
    now += 2_000;
    await yes.isEntitled('a');
    expect(positive).toHaveBeenCalledTimes(2);

    const negative = vi.fn(async () => revenueCatResponse('plus', undefined));
    vi.stubGlobal('fetch', negative);
    const no = new EntitlementService(config, counters);
    await no.isEntitled('b');
    now += 59_000;
    await no.isEntitled('b');
    expect(negative).toHaveBeenCalledTimes(1);
    now += 2_000;
    await no.isEntitled('b');
    expect(negative).toHaveBeenCalledTimes(2);
  });

  it('does not cache upstream failures as "not entitled"', async () => {
    const fetchMock = vi.fn(async () => new Response('boom', { status: 503 }));
    vi.stubGlobal('fetch', fetchMock);

    const svc = service(liveEnv);
    await expect(svc.isEntitled('user-1')).rejects.toBeInstanceOf(ApiError);
    await expect(svc.isEntitled('user-1')).rejects.toBeInstanceOf(ApiError);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('returns 401 not_entitled through the HTTP layer', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => revenueCatResponse('plus', undefined)));
    await withEnv(liveEnv, async () => {
      const res = await callStrava('Bearer nobody');
      expect(res.status).toBe(401);
      expect((await errOf(res)).code).toBe('not_entitled');
    });
  });

  it('degrades to 503 when live mode has no secret key', async () => {
    await withEnv({ ...liveEnv, REVENUECAT_SECRET_KEY: '' }, async () => {
      const res = await callStrava('Bearer someone');
      expect(res.status).toBe(503);
      expect((await errOf(res)).code).toBe('unavailable');
    });
  });
});
