// SPDX-License-Identifier: AGPL-3.0-only
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  AUTH,
  errOf,
  fetchCall,
  testApp,
} from './helpers.js';

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

describe('POST /oauth/strava/token', () => {
  it('exchanges the code and passes Strava\'s JSON back unchanged', async () => {
    const fetchMock = vi.fn(async () => jsonResponse(STRAVA_TOKEN_RESPONSE));
    vi.stubGlobal('fetch', fetchMock);

    const app = testApp({ env });
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/strava/token',
      headers: AUTH,
      payload: { code: 'the-code', redirect_uri: 'velorki://oauth/strava' },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual(STRAVA_TOKEN_RESPONSE);

    const { url, init } = fetchCall(fetchMock);
    expect(url).toBe('https://www.strava.com/oauth/token');
    const form = new URLSearchParams(init.body as string);
    expect(Object.fromEntries(form)).toEqual({
      client_id: '99887',
      client_secret: 'super-secret-strava-value',
      code: 'the-code',
      grant_type: 'authorization_code',
    });
    await app.close();
  });

  it('rejects a redirect_uri that is not on the allowlist', async () => {
    const fetchMock = vi.fn(async () => jsonResponse(STRAVA_TOKEN_RESPONSE));
    vi.stubGlobal('fetch', fetchMock);

    const app = testApp({ env });
    for (const redirect of [
      'velorki://oauth/evil',
      'velorki://oauth/strava/extra',
      'https://velorki.com/oauth/callback?x=1',
      '',
    ]) {
      const res = await app.inject({
        method: 'POST',
        url: '/oauth/strava/token',
        headers: AUTH,
        payload: { code: 'c', redirect_uri: redirect },
      });
      expect(res.statusCode, redirect).toBe(400);
      expect(errOf(res).code).toBe('invalid_request');
    }
    // Nothing must have reached Strava.
    expect(fetchMock).not.toHaveBeenCalled();
    await app.close();
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

    const app = testApp({ env });
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/strava/token',
      headers: AUTH,
      payload: { code: 'c', redirect_uri: 'velorki://oauth/strava' },
    });

    expect(res.statusCode).toBe(502);
    expect(errOf(res).code).toBe('upstream_error');
    expect(errOf(res).message).toContain('Bad Request');
    expect(res.payload).not.toContain('super-secret-strava-value');
    await app.close();
  });

  it('scrubs the secret even when the provider echoes it back', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () =>
        jsonResponse({ message: 'invalid client_secret super-secret-strava-value' }, 401),
      ),
    );
    const app = testApp({ env });
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/strava/token',
      headers: AUTH,
      payload: { code: 'c', redirect_uri: 'velorki://oauth/strava' },
    });
    expect(res.payload).not.toContain('super-secret-strava-value');
    expect(errOf(res).message).toContain('[redacted]');
    await app.close();
  });

  it('returns 502 when Strava cannot be reached', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error('ETIMEDOUT');
      }),
    );
    const app = testApp({ env });
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/strava/token',
      headers: AUTH,
      payload: { code: 'c', redirect_uri: 'velorki://oauth/strava' },
    });
    expect(res.statusCode).toBe(502);
    await app.close();
  });

  it('rejects a body that does not match the schema', async () => {
    const app = testApp({ env });
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/strava/token',
      headers: AUTH,
      payload: { redirect_uri: 'velorki://oauth/strava' },
    });
    expect(res.statusCode).toBe(400);
    expect(errOf(res).code).toBe('invalid_request');
    await app.close();
  });

  it('degrades to 503 when Strava is not configured', async () => {
    const app = testApp({ env: { OAUTH_REDIRECT_ALLOWLIST: 'velorki://oauth/strava' } });
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/strava/token',
      headers: AUTH,
      payload: { code: 'c', redirect_uri: 'velorki://oauth/strava' },
    });
    expect(res.statusCode).toBe(503);
    expect(errOf(res).code).toBe('unavailable');
    await app.close();
  });
});

describe('POST /oauth/strava/refresh', () => {
  it('sends grant_type=refresh_token and passes the answer through', async () => {
    const fetchMock = vi.fn(async () => jsonResponse(STRAVA_TOKEN_RESPONSE));
    vi.stubGlobal('fetch', fetchMock);

    const app = testApp({ env });
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/strava/refresh',
      headers: AUTH,
      payload: { refresh_token: 'r0' },
    });

    expect(res.statusCode).toBe(200);
    const form = new URLSearchParams(fetchCall(fetchMock).init.body as string);
    expect(form.get('grant_type')).toBe('refresh_token');
    expect(form.get('refresh_token')).toBe('r0');
    await app.close();
  });
});

describe('Ride with GPS', () => {
  it('posts the redirect_uri along with the code', async () => {
    const fetchMock = vi.fn(async () => jsonResponse({ access_token: 'rw-token' }));
    vi.stubGlobal('fetch', fetchMock);

    const app = testApp({ env });
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/rwgps/token',
      headers: AUTH,
      payload: { code: 'c', redirect_uri: 'https://velorki.com/oauth/callback' },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ access_token: 'rw-token' });
    const { url, init } = fetchCall(fetchMock);
    expect(url).toBe('https://ridewithgps.com/oauth/token.json');
    expect(Object.fromEntries(new URLSearchParams(init.body as string))).toEqual({
      client_id: 'rw-1',
      client_secret: 'super-secret-rwgps-value',
      code: 'c',
      grant_type: 'authorization_code',
      redirect_uri: 'https://velorki.com/oauth/callback',
    });
    await app.close();
  });

  it('answers refresh with 501 and the unavailable code', async () => {
    const app = testApp({ env });
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/rwgps/refresh',
      headers: AUTH,
      payload: { refresh_token: 'x' },
    });
    expect(res.statusCode).toBe(501);
    expect(errOf(res).code).toBe('unavailable');
    await app.close();
  });
});
