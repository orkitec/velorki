// SPDX-License-Identifier: AGPL-3.0-only
import { afterEach, describe, expect, it, vi } from 'vitest';
import { EntitlementService } from '../src/plugins/entitlement.js';
import { ApiError } from '../src/plugins/errors.js';
import {
  errOf,
  fetchCall,
  revenueCatResponse,
  testApp,
  testConfig,
} from './helpers.js';

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

async function callStrava(app: ReturnType<typeof testApp>, auth?: string) {
  return app.inject({
    method: 'POST',
    url: '/oauth/strava/token',
    headers: auth === undefined ? {} : { authorization: auth },
    payload: { code: 'abc', redirect_uri: 'velorki://oauth/strava' },
  });
}

describe('entitlement: header handling', () => {
  it('rejects a missing Authorization header with 401 not_entitled', async () => {
    const app = testApp({ env: liveEnv });
    const res = await callStrava(app);
    expect(res.statusCode).toBe(401);
    expect(errOf(res).code).toBe('not_entitled');
    await app.close();
  });

  it('rejects a malformed Authorization header', async () => {
    const app = testApp({ env: liveEnv });
    for (const header of ['Basic abc', 'Bearer', 'Bearer  ', 'token-without-scheme']) {
      const res = await callStrava(app, header);
      expect(res.statusCode, header).toBe(401);
      expect(errOf(res).code).toBe('not_entitled');
    }
    await app.close();
  });
});

describe('entitlement: stub mode', () => {
  it('treats everyone as entitled without calling RevenueCat', async () => {
    const fetchMock = vi.fn(async () => new Response('{}', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    const service = new EntitlementService(testConfig({ REVENUECAT_MODE: 'stub' }));
    await expect(service.isEntitled('anyone')).resolves.toBe(true);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe('entitlement: live mode', () => {
  it('accepts an entitlement with a null expiry', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => revenueCatResponse('plus', null)));
    const service = new EntitlementService(testConfig(liveEnv));
    await expect(service.isEntitled('user-1')).resolves.toBe(true);
  });

  it('accepts an entitlement expiring in the future', async () => {
    const future = new Date(Date.now() + 86_400_000).toISOString();
    vi.stubGlobal('fetch', vi.fn(async () => revenueCatResponse('plus', future)));
    const service = new EntitlementService(testConfig(liveEnv));
    await expect(service.isEntitled('user-1')).resolves.toBe(true);
  });

  it('rejects an expired entitlement and a missing one', async () => {
    const past = new Date(Date.now() - 1000).toISOString();
    vi.stubGlobal('fetch', vi.fn(async () => revenueCatResponse('plus', past)));
    await expect(new EntitlementService(testConfig(liveEnv)).isEntitled('u')).resolves.toBe(false);

    vi.stubGlobal('fetch', vi.fn(async () => revenueCatResponse('plus', undefined)));
    await expect(new EntitlementService(testConfig(liveEnv)).isEntitled('u')).resolves.toBe(false);
  });

  it('sends the secret key to RevenueCat and only to RevenueCat', async () => {
    const fetchMock = vi.fn(async () => revenueCatResponse('plus', null));
    vi.stubGlobal('fetch', fetchMock);

    await new EntitlementService(testConfig(liveEnv)).isEntitled('user with/slash');

    const { url, init } = fetchCall(fetchMock);
    expect(url).toBe('https://api.revenuecat.com/v1/subscribers/user%20with%2Fslash');
    expect((init.headers as Record<string, string>).authorization).toBe('Bearer sk_test_do_not_log');
  });

  it('caches the positive answer instead of asking again', async () => {
    const fetchMock = vi.fn(async () => revenueCatResponse('plus', null));
    vi.stubGlobal('fetch', fetchMock);

    const service = new EntitlementService(testConfig(liveEnv));
    await service.isEntitled('same-user');
    await service.isEntitled('same-user');
    await service.isEntitled('same-user');
    expect(fetchMock).toHaveBeenCalledTimes(1);

    // A different user is a different cache entry.
    await service.isEntitled('other-user');
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('caches the negative answer too', async () => {
    const fetchMock = vi.fn(async () => revenueCatResponse('plus', undefined));
    vi.stubGlobal('fetch', fetchMock);

    const service = new EntitlementService(testConfig(liveEnv));
    await service.isEntitled('freeloader');
    await service.isEntitled('freeloader');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('does not cache upstream failures as "not entitled"', async () => {
    const fetchMock = vi.fn(async () => new Response('boom', { status: 503 }));
    vi.stubGlobal('fetch', fetchMock);

    const service = new EntitlementService(testConfig(liveEnv));
    await expect(service.isEntitled('user-1')).rejects.toBeInstanceOf(ApiError);
    await expect(service.isEntitled('user-1')).rejects.toBeInstanceOf(ApiError);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('returns 401 not_entitled through the HTTP layer', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => revenueCatResponse('plus', undefined)));
    const app = testApp({ env: liveEnv });
    const res = await callStrava(app, 'Bearer nobody');
    expect(res.statusCode).toBe(401);
    expect(errOf(res).code).toBe('not_entitled');
    await app.close();
  });

  it('degrades to 503 when live mode has no secret key', async () => {
    const app = testApp({ env: { ...liveEnv, REVENUECAT_SECRET_KEY: '' } });
    const res = await callStrava(app, 'Bearer someone');
    expect(res.statusCode).toBe(503);
    expect(errOf(res).code).toBe('unavailable');
    await app.close();
  });
});
