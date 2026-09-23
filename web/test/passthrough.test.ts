// SPDX-License-Identifier: AGPL-3.0-only
import { pino } from 'pino';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { GET as stravaGet, POST as stravaPost } from '@/app/(api)/proxy/strava/[...path]/route';
import { GET as rwgpsGet, POST as rwgpsPost } from '@/app/(api)/proxy/rwgps/[...path]/route';
import { matchUpstream, upstreamPath } from '@/server/passthrough';
import { injectSingletons } from '@/server/singletons';
import { parseWrapKeys, wrapToken } from '@/server/wrap';
import {
  AUTH,
  TEST_WRAP_KEYS,
  WRAP_KEY_1,
  errOf,
  fetchCall,
  revenueCatResponse,
  withEnv,
} from './helpers';

afterEach(() => {
  vi.unstubAllGlobals();
});

const API = 'https://api.velorki.com';
const keys = parseWrapKeys(TEST_WRAP_KEYS);
const PLAIN = 'strava-access-token-in-clear';
const WRAPPED = wrapToken(keys, 'strava', 'access', PLAIN);
const TOKEN = { ...AUTH, 'x-velorki-token': WRAPPED };

function upstreamOk(body = '{"id": 1}', headers: Record<string, string> = {}): Response {
  return new Response(body, {
    status: 201,
    headers: { 'content-type': 'application/json', 'set-cookie': 'sid=1', ...headers },
  });
}

describe('upstreamPath and the allowlist', () => {
  it('takes what follows /proxy/<service>, from a rewritten path too', () => {
    expect(upstreamPath('/proxy/strava/api/v3/uploads', 'strava')).toBe('/api/v3/uploads');
    expect(upstreamPath('/__api/proxy/rwgps/api/v1/routes.json/', 'rwgps')).toBe(
      '/api/v1/routes.json',
    );
    expect(upstreamPath('/proxy/strava/', 'strava')).toBeUndefined();
    expect(upstreamPath('/proxy/rwgps/x', 'strava')).toBeUndefined();
  });

  it('knows exactly the calls the app makes', () => {
    const yes: [('strava' | 'rwgps'), string, string, string][] = [
      ['strava', 'POST', '/api/v3/uploads', 'upload'],
      ['strava', 'GET', '/api/v3/uploads/1234', 'upload_status'],
      ['strava', 'GET', '/api/v3/athletes/7/routes', 'list_routes'],
      ['strava', 'GET', '/api/v3/routes/99/export_gpx', 'route_gpx'],
      ['strava', 'POST', '/oauth/deauthorize', 'deauthorize'],
      ['rwgps', 'GET', '/api/v1/users/current.json', 'user'],
      ['rwgps', 'POST', '/api/v1/routes.json', 'upload_route'],
      ['rwgps', 'POST', '/api/v1/trips.json', 'upload_trip'],
      ['rwgps', 'GET', '/api/v1/tasks/5.json', 'task'],
      ['rwgps', 'GET', '/api/v1/routes.json', 'list_routes'],
      ['rwgps', 'GET', '/api/v1/trips.json', 'list_trips'],
      ['rwgps', 'GET', '/api/v1/routes/42.gpx', 'route_gpx'],
      ['rwgps', 'POST', '/oauth/revoke.json', 'revoke'],
    ];
    for (const [service, method, path, operation] of yes) {
      expect(matchUpstream(service, method, path)?.operation, `${method} ${path}`).toBe(operation);
    }
    const no: [('strava' | 'rwgps'), string, string][] = [
      ['strava', 'GET', '/api/v3/athlete'],
      ['strava', 'GET', '/api/v3/athlete/activities'],
      ['strava', 'DELETE', '/api/v3/uploads/1'],
      ['strava', 'GET', '/api/v3/uploads/abc'],
      ['strava', 'GET', '/api/v3/routes/1/export_gpx/../../athlete'],
      ['strava', 'POST', '/oauth/token'],
      ['rwgps', 'GET', '/api/v1/users/1.json'],
      ['rwgps', 'GET', '/oauth/revoke.json'],
      ['strava', 'POST', '/oauth/revoke.json'],
      ['rwgps', 'GET', '/api/v1/routes/42.json'],
    ];
    for (const [service, method, path] of no) {
      expect(matchUpstream(service, method, path), `${method} ${path}`).toBeUndefined();
    }
  });
});

describe('/proxy/<service>/*', () => {
  it('needs an entitled rider before anything else', async () => {
    const fetchMock = vi.fn(async () => upstreamOk());
    vi.stubGlobal('fetch', fetchMock);
    await withEnv({}, async () => {
      const res = await stravaGet(
        new Request(`${API}/proxy/strava/api/v3/uploads/1`, {
          headers: { 'x-velorki-token': WRAPPED },
        }),
      );
      expect(res.status).toBe(401);
      expect((await errOf(res)).code).toBe('not_entitled');
      expect(fetchMock).not.toHaveBeenCalled();
    });
  });

  it('refuses a lapsed subscription with the same answer', async () => {
    const fetchMock = vi.fn(async () => revenueCatResponse('plus', undefined));
    vi.stubGlobal('fetch', fetchMock);
    await withEnv({ REVENUECAT_MODE: 'live', REVENUECAT_SECRET_KEY: 'sk' }, async () => {
      const res = await stravaGet(
        new Request(`${API}/proxy/strava/api/v3/uploads/1`, { headers: TOKEN }),
      );
      expect(res.status).toBe(401);
      // Only RevenueCat was called; Strava never was.
      expect(fetchMock).toHaveBeenCalledTimes(1);
    });
  });

  it('404s anything off the allowlist, before the rate limit is charged', async () => {
    const fetchMock = vi.fn(async () => upstreamOk());
    vi.stubGlobal('fetch', fetchMock);
    await withEnv({}, async (ctx) => {
      for (const [handler, path] of [
        [stravaGet, '/proxy/strava/api/v3/athlete'],
        [stravaPost, '/proxy/strava/api/v3/uploads/1'],
        [rwgpsGet, '/proxy/rwgps/api/v1/routes/1.json'],
        [rwgpsPost, '/proxy/rwgps/oauth/token.json'],
      ] as const) {
        const res = await handler(
          new Request(`${API}${path}`, {
            method: handler === stravaPost || handler === rwgpsPost ? 'POST' : 'GET',
            headers: TOKEN,
          }),
        );
        expect(res.status, path).toBe(404);
        expect((await errOf(res)).code).toBe('not_found');
      }
      expect(fetchMock).not.toHaveBeenCalled();
      expect(await ctx.counters.get('rl:proxy_min:user-42:' + String(Math.floor(Date.now() / 60_000) * 60))).toBeUndefined();
    });
  });

  it('rewrites the auth header, drops ours, and streams the body both ways', async () => {
    const fetchMock = vi.fn(async (_input: unknown, init?: RequestInit) => {
      const received = await new Response(init?.body as ReadableStream<Uint8Array>).text();
      return upstreamOk(`{"echo":${JSON.stringify(received)}}`, {
        'content-length': '99',
        'x-ratelimit-usage': '3,10',
      });
    });
    vi.stubGlobal('fetch', fetchMock);
    await withEnv({}, async () => {
      const form = new FormData();
      form.set('data_type', 'fit');
      form.set('file', new Blob([new Uint8Array([1, 2, 3, 4])]), 'ride.fit');
      const request = new Request(`${API}/proxy/strava/api/v3/uploads?x=1&access_token=leak`, {
        method: 'POST',
        headers: { ...TOKEN, 'x-request-id': 'r-1', cookie: 'a=b', 'x-velorki-client': 'ios/1' },
        body: form,
      });
      const res = await stravaPost(request);

      expect(res.status).toBe(201);
      const { url, init } = fetchCall(fetchMock);
      expect(url).toBe('https://www.strava.com/api/v3/uploads?x=1');
      expect(init.method).toBe('POST');
      const sent = new Headers(init.headers);
      expect(sent.get('authorization')).toBe(`Bearer ${PLAIN}`);
      expect(sent.get('content-type')).toContain('multipart/form-data');
      expect(sent.get('x-velorki-token')).toBeNull();
      expect(sent.get('cookie')).toBeNull();
      expect(sent.get('x-request-id')).toBeNull();
      expect(sent.get('x-velorki-client')).toBeNull();
      expect((init as { duplex?: string }).duplex).toBe('half');

      const body = (await res.json()) as { echo: string };
      expect(body.echo).toContain('name="file"; filename="ride.fit"');
      expect(body.echo).toContain('name="data_type"');
      expect(res.headers.get('x-ratelimit-usage')).toBe('3,10');
      expect(res.headers.get('set-cookie')).toBeNull();
      expect(res.headers.get('x-velorki-token-rewrapped')).toBeNull();
      expect(res.headers.get('x-request-id')).toBe('r-1');
      expect(res.headers.get('cache-control')).toBe('no-store');
    });
  });

  it('revokes a Ride with GPS token with the client secret the relay holds', async () => {
    const fetchMock = vi.fn(async () => new Response('{}', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);
    const env = { RWGPS_CLIENT_ID: 'rw-1', RWGPS_CLIENT_SECRET: 'rw-secret' };
    await withEnv(env, async () => {
      const res = await rwgpsPost(
        new Request(`${API}/proxy/rwgps/oauth/revoke.json`, {
          method: 'POST',
          headers: {
            ...AUTH,
            'x-velorki-token': wrapToken(keys, 'rwgps', 'access', 'rw-clear'),
            'content-type': 'text/plain',
          },
          body: 'ignored',
        }),
      );
      expect(res.status).toBe(200);
      const { url, init } = fetchCall(fetchMock);
      expect(url).toBe('https://ridewithgps.com/oauth/revoke.json');
      const sent = new Headers(init.headers);
      // The secret and the clear token go in the body, as the service
      // documents; no bearer, and nothing of the phone's request.
      expect(sent.get('content-type')).toBe('application/json');
      expect(sent.get('authorization')).toBeNull();
      expect(JSON.parse(init.body as string)).toEqual({
        client_id: 'rw-1',
        client_secret: 'rw-secret',
        token: 'rw-clear',
      });
    });
    // Without the credentials the call is a 503, and nothing goes out.
    fetchMock.mockClear();
    await withEnv({}, async () => {
      const res = await rwgpsPost(
        new Request(`${API}/proxy/rwgps/oauth/revoke.json`, {
          method: 'POST',
          headers: { ...AUTH, 'x-velorki-token': wrapToken(keys, 'rwgps', 'access', 'rw') },
        }),
      );
      expect(res.status).toBe(503);
      expect(fetchMock).not.toHaveBeenCalled();
    });
  });

  it('passes an upstream error status and body back unchanged', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response('{"message":"Rate Limit Exceeded"}', { status: 429 })),
    );
    await withEnv({}, async () => {
      const res = await rwgpsGet(
        new Request(`${API}/proxy/rwgps/api/v1/routes.json?page=2`, {
          headers: { ...AUTH, 'x-velorki-token': wrapToken(keys, 'rwgps', 'access', 'rw') },
        }),
      );
      expect(res.status).toBe(429);
      expect(await res.text()).toBe('{"message":"Rate Limit Exceeded"}');
    });
  });

  it('re-wraps a token that arrived under an old key', async () => {
    const fetchMock = vi.fn(async () => upstreamOk());
    vi.stubGlobal('fetch', fetchMock);
    const oldWrapped = wrapToken(parseWrapKeys(WRAP_KEY_1), 'strava', 'access', PLAIN);
    await withEnv({}, async () => {
      const res = await stravaGet(
        new Request(`${API}/proxy/strava/api/v3/uploads/1`, {
          headers: { ...AUTH, 'x-velorki-token': oldWrapped },
        }),
      );
      expect(res.status).toBe(201);
      const fresh = res.headers.get('x-velorki-token-rewrapped');
      expect(fresh).toMatch(/^v1\.k2\./);
      expect(new Headers(fetchCall(fetchMock).init.headers).get('authorization')).toBe(
        `Bearer ${PLAIN}`,
      );
    });
  });

  it('answers 400 for a missing, foreign or forged token, 503 without keys', async () => {
    const fetchMock = vi.fn(async () => upstreamOk());
    vi.stubGlobal('fetch', fetchMock);
    await withEnv({}, async () => {
      for (const token of [
        undefined,
        'garbage',
        wrapToken(keys, 'rwgps', 'access', PLAIN),
        wrapToken(keys, 'strava', 'refresh', PLAIN),
      ]) {
        const res = await stravaGet(
          new Request(`${API}/proxy/strava/api/v3/uploads/1`, {
            headers: token === undefined ? AUTH : { ...AUTH, 'x-velorki-token': token },
          }),
        );
        expect(res.status, token ?? 'missing').toBe(400);
        expect((await errOf(res)).code).toBe('invalid_request');
      }
      expect(fetchMock).not.toHaveBeenCalled();
    });
    await withEnv({ TOKEN_WRAP_KEYS: '' }, async () => {
      const res = await stravaGet(
        new Request(`${API}/proxy/strava/api/v3/uploads/1`, { headers: TOKEN }),
      );
      expect(res.status).toBe(503);
      expect((await errOf(res)).code).toBe('unavailable');
    });
  });

  it('turns an unreachable service into 502 and a huge body into 400', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error('ECONNRESET');
      }),
    );
    await withEnv({}, async () => {
      const res = await stravaGet(
        new Request(`${API}/proxy/strava/api/v3/uploads/1`, { headers: TOKEN }),
      );
      expect(res.status).toBe(502);
      expect((await errOf(res)).message).toBe('Could not reach Strava.');

      const big = await stravaPost(
        new Request(`${API}/proxy/strava/api/v3/uploads`, {
          method: 'POST',
          headers: { ...TOKEN, 'content-length': String(30 * 1024 * 1024) },
          body: 'x',
        }),
      );
      expect(big.status).toBe(400);
    });
  });

  it('rate limits per rider', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => upstreamOk()));
    await withEnv({}, async () => {
      const call = (auth: string) =>
        stravaGet(
          new Request(`${API}/proxy/strava/api/v3/uploads/1`, {
            headers: { authorization: auth, 'x-velorki-token': WRAPPED },
          }),
        );
      for (let i = 0; i < 60; i += 1) expect((await call('Bearer a')).status).toBe(201);
      const limited = await call('Bearer a');
      expect(limited.status).toBe(429);
      expect(limited.headers.get('retry-after')).toBeTruthy();
      expect((await call('Bearer b')).status).toBe(201);
    });
  });

  it('leaves no record of the call but the rate-limit window', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => upstreamOk()));
    await withEnv({}, async (ctx) => {
      await stravaGet(
        new Request(`${API}/proxy/strava/api/v3/uploads/1`, { headers: TOKEN }),
      );
      const keys = [...ctx.counters.keys()];
      expect(keys.filter((k) => k.startsWith('rl:proxy_'))).toHaveLength(2);
      expect(keys.filter((k) => !k.startsWith('rl:'))).toEqual([]);
    });
  });

  it('never writes the token, wrapped or clear, or the body to the log', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error(`refused ${PLAIN}`);
      }),
    );
    const lines: string[] = [];
    const logger = pino({ level: 'trace' }, { write: (line: string) => void lines.push(line) });
    await withEnv({}, async () => {
      injectSingletons({ logger });
      const res = await stravaPost(
        new Request(`${API}/proxy/strava/api/v3/uploads`, {
          method: 'POST',
          headers: { ...TOKEN, 'content-type': 'text/plain' },
          body: 'the-ride-file-contents',
        }),
      );
      expect(res.status).toBe(502);
    });
    expect(lines.length).toBeGreaterThan(0);
    const joined = lines.join('\n');
    expect(joined).toContain('upstream unreachable');
    expect(joined).not.toContain(PLAIN);
    expect(joined).not.toContain(WRAPPED);
    expect(joined).not.toContain('the-ride-file-contents');
    expect(joined).not.toContain('user-42');
  });
});
