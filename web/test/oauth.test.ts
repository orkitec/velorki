// SPDX-License-Identifier: AGPL-3.0-only
import { afterEach, describe, expect, it, vi } from 'vitest';
import { POST as stravaToken } from '@/app/(api)/oauth/strava/token/route';
import { POST as stravaRefresh } from '@/app/(api)/oauth/strava/refresh/route';
import { POST as rwgpsToken } from '@/app/(api)/oauth/rwgps/token/route';
import { POST as rwgpsRefresh } from '@/app/(api)/oauth/rwgps/refresh/route';
import { AUTH, errOf, fetchCall, jsonRequest, withEnv } from './helpers';

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
  it("exchanges the code and passes Strava's JSON back unchanged", async () => {
    const fetchMock = vi.fn(async () => jsonResponse(STRAVA_TOKEN_RESPONSE));
    vi.stubGlobal('fetch', fetchMock);

    await withEnv(env, async () => {
      const res = await stravaToken(
        jsonRequest(STRAVA_URL, { code: 'the-code', redirect_uri: 'velorki://oauth/strava' }, AUTH),
      );

      expect(res.status).toBe(200);
      expect(await res.json()).toEqual(STRAVA_TOKEN_RESPONSE);
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
});

describe('POST /oauth/strava/refresh', () => {
  it('sends grant_type=refresh_token and passes the answer through', async () => {
    const fetchMock = vi.fn(async () => jsonResponse(STRAVA_TOKEN_RESPONSE));
    vi.stubGlobal('fetch', fetchMock);

    await withEnv(env, async () => {
      const res = await stravaRefresh(
        jsonRequest('https://api.velorki.com/oauth/strava/refresh', { refresh_token: 'r0' }, AUTH),
      );
      expect(res.status).toBe(200);
      const form = new URLSearchParams(fetchCall(fetchMock).init.body as string);
      expect(form.get('grant_type')).toBe('refresh_token');
      expect(form.get('refresh_token')).toBe('r0');
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
      expect(await res.json()).toEqual({ access_token: 'rw-token' });
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
