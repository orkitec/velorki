// SPDX-License-Identifier: AGPL-3.0-only
import { afterEach, describe, expect, it, vi } from 'vitest';
import { POST as stravaToken } from '@/app/(api)/oauth/strava/token/route';
import { POST as stravaRefresh } from '@/app/(api)/oauth/strava/refresh/route';
import { POST as rwgpsToken } from '@/app/(api)/oauth/rwgps/token/route';
import { POST as rwgpsRefresh } from '@/app/(api)/oauth/rwgps/refresh/route';
import { parseWrapKeys, unwrapToken, wrapToken } from '@/server/wrap';
import { AUTH, TEST_WRAP_KEYS, errOf, fetchCall, jsonRequest, withEnv } from './helpers';

const keys = parseWrapKeys(TEST_WRAP_KEYS);

/** The provider's answer as the phone sees it: tokens opened again for the assertion. */
async function unwrappedBody(res: Response, service: 'strava' | 'rwgps'): Promise<unknown> {
  const body = (await res.json()) as Record<string, unknown>;
  const out = { ...body };
  if (typeof body['access_token'] === 'string') {
    expect(body['access_token']).toMatch(/^v1\.k2\./);
    out['access_token'] = unwrapToken(keys, service, 'access', body['access_token']).token;
  }
  if (typeof body['refresh_token'] === 'string') {
    expect(body['refresh_token']).toMatch(/^v1\.k2\./);
    out['refresh_token'] = unwrapToken(keys, service, 'refresh', body['refresh_token']).token;
  }
  return out;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

const env = {
  STRAVA_CLIENT_ID: '99887',
  STRAVA_CLIENT_SECRET: 'super-secret-strava-value',
  RWGPS_CLIENT_ID: 'rw-1',
  RWGPS_CLIENT_SECRET: 'super-secret-rwgps-value',
  OAUTH_REDIRECT_ALLOWLIST: 'velorki://oauth/strava,https://velorki.com/oauth/callback',
};

const STRAVA_TOKEN_RESPONSE = {
  token_type: 'Bearer',
  access_token: 'a1',
  refresh_token: 'r1',
  expires_at: 1893456000,
  athlete: { id: 7 },
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

const STRAVA_URL = 'https://api.velorki.com/oauth/strava/token';

describe('POST /oauth/strava/token', () => {
  it("exchanges the code and passes Strava's JSON back with the tokens wrapped", async () => {
    const fetchMock = vi.fn(async () => jsonResponse(STRAVA_TOKEN_RESPONSE));
    vi.stubGlobal('fetch', fetchMock);

    await withEnv(env, async () => {
      const res = await stravaToken(
        jsonRequest(STRAVA_URL, { code: 'the-code', redirect_uri: 'velorki://oauth/strava' }, AUTH),
      );

      expect(res.status).toBe(200);
      const raw = await res.clone().text();
      expect(raw).not.toContain('"a1"');
      expect(raw).not.toContain('"r1"');
      expect(await unwrappedBody(res, 'strava')).toEqual(STRAVA_TOKEN_RESPONSE);
      expect(res.headers.get('cache-control')).toBe('no-store');

      const { url, init } = fetchCall(fetchMock);
      expect(url).toBe('https://www.strava.com/oauth/token');
      const form = new URLSearchParams(init.body as string);
      expect(Object.fromEntries(form)).toEqual({
        client_id: '99887',
        client_secret: 'super-secret-strava-value',
        code: 'the-code',
        grant_type: 'authorization_code',
      });
    });
  });

  it('rejects a redirect_uri that is not on the allowlist', async () => {
    const fetchMock = vi.fn(async () => jsonResponse(STRAVA_TOKEN_RESPONSE));
    vi.stubGlobal('fetch', fetchMock);

    await withEnv(env, async () => {
      for (const redirect of [
        'velorki://oauth/evil',
        'velorki://oauth/strava/extra',
        'https://velorki.com/oauth/callback?x=1',
        '',
      ]) {
        const res = await stravaToken(
          jsonRequest(STRAVA_URL, { code: 'c', redirect_uri: redirect }, AUTH),
        );
        expect(res.status, redirect).toBe(400);
        expect((await errOf(res)).code).toBe('invalid_request');
      }
      // Nothing must have reached Strava.
      expect(fetchMock).not.toHaveBeenCalled();
    });
  });

  it('turns an upstream failure into 502 without leaking the secret', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () =>
        jsonResponse(
          {
            message: 'Bad Request',
            errors: [{ resource: 'Application', field: 'client_secret', code: 'invalid' }],
          },
          400,
        ),
      ),
    );

    await withEnv(env, async () => {
      const res = await stravaToken(
        jsonRequest(STRAVA_URL, { code: 'c', redirect_uri: 'velorki://oauth/strava' }, AUTH),
      );
      const payload = await res.clone().text();

      expect(res.status).toBe(502);
      expect((await errOf(res)).code).toBe('upstream_error');
      expect(payload).toContain('Bad Request');
      expect(payload).not.toContain('super-secret-strava-value');
    });
  });

  it('scrubs the secret even when the provider echoes it back', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () =>
        jsonResponse({ message: 'invalid client_secret super-secret-strava-value' }, 401),
      ),
    );
    await withEnv(env, async () => {
      const res = await stravaToken(
        jsonRequest(STRAVA_URL, { code: 'c', redirect_uri: 'velorki://oauth/strava' }, AUTH),
      );
      const payload = await res.clone().text();
      expect(payload).not.toContain('super-secret-strava-value');
      expect((await errOf(res)).message).toContain('[redacted]');
    });
  });

  it('returns 502 when Strava cannot be reached', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error('ETIMEDOUT');
      }),
    );
    await withEnv(env, async () => {
      const res = await stravaToken(
        jsonRequest(STRAVA_URL, { code: 'c', redirect_uri: 'velorki://oauth/strava' }, AUTH),
      );
      expect(res.status).toBe(502);
    });
  });

  it('rejects a body that does not match the schema', async () => {
    await withEnv(env, async () => {
      const res = await stravaToken(
        jsonRequest(STRAVA_URL, { redirect_uri: 'velorki://oauth/strava' }, AUTH),
      );
      expect(res.status).toBe(400);
      expect((await errOf(res)).code).toBe('invalid_request');
    });
  });

  it('degrades to 503 when Strava is not configured', async () => {
    await withEnv({ OAUTH_REDIRECT_ALLOWLIST: 'velorki://oauth/strava' }, async () => {
      const res = await stravaToken(
        jsonRequest(STRAVA_URL, { code: 'c', redirect_uri: 'velorki://oauth/strava' }, AUTH),
      );
      expect(res.status).toBe(503);
      expect((await errOf(res)).code).toBe('unavailable');
    });
  });

  it('degrades to 503 without a wrapping key, before Strava is called', async () => {
    const fetchMock = vi.fn(async () => jsonResponse(STRAVA_TOKEN_RESPONSE));
    vi.stubGlobal('fetch', fetchMock);
    await withEnv({ ...env, TOKEN_WRAP_KEYS: '' }, async () => {
      const res = await stravaToken(
        jsonRequest(STRAVA_URL, { code: 'c', redirect_uri: 'velorki://oauth/strava' }, AUTH),
      );
      expect(res.status).toBe(503);
      expect((await errOf(res)).code).toBe('unavailable');
      expect(fetchMock).not.toHaveBeenCalled();
    });
  });
});

describe('POST /oauth/strava/refresh', () => {
  const REFRESH_URL = 'https://api.velorki.com/oauth/strava/refresh';

  it('unwraps the refresh token, sends grant_type=refresh_token and wraps the answer', async () => {
    const fetchMock = vi.fn(async () => jsonResponse(STRAVA_TOKEN_RESPONSE));
    vi.stubGlobal('fetch', fetchMock);

    await withEnv(env, async () => {
      const res = await stravaRefresh(
        jsonRequest(
          REFRESH_URL,
          { refresh_token: wrapToken(keys, 'strava', 'refresh', 'r0') },
          AUTH,
        ),
      );
      expect(res.status).toBe(200);
      const form = new URLSearchParams(fetchCall(fetchMock).init.body as string);
      expect(form.get('grant_type')).toBe('refresh_token');
      expect(form.get('refresh_token')).toBe('r0');
      expect(await unwrappedBody(res, 'strava')).toEqual(STRAVA_TOKEN_RESPONSE);
    });
  });

  it('refuses a clear or foreign refresh token without calling Strava', async () => {
    const fetchMock = vi.fn(async () => jsonResponse(STRAVA_TOKEN_RESPONSE));
    vi.stubGlobal('fetch', fetchMock);
    await withEnv(env, async () => {
      for (const token of ['r0', wrapToken(keys, 'strava', 'access', 'r0')]) {
        const res = await stravaRefresh(jsonRequest(REFRESH_URL, { refresh_token: token }, AUTH));
        expect(res.status).toBe(400);
        expect((await errOf(res)).code).toBe('invalid_request');
      }
      expect(fetchMock).not.toHaveBeenCalled();
    });
  });
});

describe('Ride with GPS', () => {
  it('posts the redirect_uri along with the code', async () => {
    const fetchMock = vi.fn(async () => jsonResponse({ access_token: 'rw-token' }));
    vi.stubGlobal('fetch', fetchMock);

    await withEnv(env, async () => {
      const res = await rwgpsToken(
        jsonRequest(
          'https://api.velorki.com/oauth/rwgps/token',
          { code: 'c', redirect_uri: 'https://velorki.com/oauth/callback' },
          AUTH,
        ),
      );

      expect(res.status).toBe(200);
      expect(await res.clone().text()).not.toContain('rw-token');
      expect(await unwrappedBody(res, 'rwgps')).toEqual({ access_token: 'rw-token' });
      const { url, init } = fetchCall(fetchMock);
      expect(url).toBe('https://ridewithgps.com/oauth/token.json');
      expect(Object.fromEntries(new URLSearchParams(init.body as string))).toEqual({
        client_id: 'rw-1',
        client_secret: 'super-secret-rwgps-value',
        code: 'c',
        grant_type: 'authorization_code',
        redirect_uri: 'https://velorki.com/oauth/callback',
      });
    });
  });

  it('answers refresh with 501 and the unavailable code', async () => {
    await withEnv(env, async () => {
      const res = await rwgpsRefresh(
        jsonRequest('https://api.velorki.com/oauth/rwgps/refresh', { refresh_token: 'x' }, AUTH),
      );
      expect(res.status).toBe(501);
      expect((await errOf(res)).code).toBe('unavailable');
    });
  });
});
