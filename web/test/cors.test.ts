// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it, vi } from 'vitest';
import { NextRequest, NextResponse } from 'next/server';
import proxy from '@/proxy';
import { loadConfig } from '@/config';
import { allowedOrigin, applyCors, corsMethods, preflightHeaders } from '@/server/cors';
import { withEnv } from './helpers';

vi.mock('next-intl/middleware', () => ({
  default: () => () => NextResponse.next(),
}));

const APP = 'https://app.velorki.com';
const ORIGINS = [APP, 'http://localhost:5000'];
const API = 'https://api.velorki.com';

function req(url: string, method: string, headers: Record<string, string> = {}): NextRequest {
  return new NextRequest(url, {
    method,
    headers: { host: new URL(url).host, ...headers },
  });
}

describe('CORS_ORIGINS config', () => {
  it('defaults to the web planner', () => {
    expect(loadConfig({}).CORS_ORIGINS).toEqual([APP]);
  });
  it('parses a list, trims and drops trailing slashes', () => {
    expect(
      loadConfig({ CORS_ORIGINS: ' https://a.test/ , http://localhost:5000' }).CORS_ORIGINS,
    ).toEqual(['https://a.test', 'http://localhost:5000']);
  });
  it('empty disables', () => {
    expect(loadConfig({ CORS_ORIGINS: '' }).CORS_ORIGINS).toEqual([]);
    expect(loadConfig({ CORS_ORIGINS: ' , ' }).CORS_ORIGINS).toEqual([]);
  });
  it('rejects a value that is not an origin', () => {
    expect(() => loadConfig({ CORS_ORIGINS: 'app.velorki.com' })).toThrow(/CORS_ORIGINS/);
    expect(() => loadConfig({ CORS_ORIGINS: 'https://a.test/path' })).toThrow(/CORS_ORIGINS/);
  });
});

describe('cors helpers', () => {
  it('knows the browser routes and their methods', () => {
    expect(corsMethods('/share')).toEqual(['POST']);
    expect(corsMethods('/share/')).toEqual(['POST']);
    expect(corsMethods('/weather/radar/opera/frames')).toEqual(['GET']);
    expect(corsMethods('/weather/radar/opera/')).toBeNull();
    expect(corsMethods('/oauth/strava/token')).toBeNull();
    expect(corsMethods('/proxy/strava/x')).toBeNull();
    expect(corsMethods('/brouter')).toBeNull();
  });
  it('matches origins exactly', () => {
    expect(allowedOrigin(ORIGINS, APP)).toBe(APP);
    expect(allowedOrigin(ORIGINS, 'https://app.velorki.com.evil.test')).toBeNull();
    expect(allowedOrigin(ORIGINS, 'null')).toBeNull();
    expect(allowedOrigin(ORIGINS, null)).toBeNull();
    expect(allowedOrigin([], APP)).toBeNull();
  });
  it('builds preflight headers without credentials or wildcard', () => {
    const h = preflightHeaders(ORIGINS, '/ai/plan', APP)!;
    expect(h['access-control-allow-origin']).toBe(APP);
    expect(h['access-control-allow-methods']).toBe('POST, OPTIONS');
    expect(h['access-control-allow-headers']).toContain('X-AI-Consent');
    expect(h['access-control-allow-headers']).toContain('Authorization');
    expect(h['access-control-max-age']).toBe('600');
    expect(h.vary).toBe('Origin');
    expect(h['access-control-allow-credentials']).toBeUndefined();
    expect(preflightHeaders(ORIGINS, '/ai/plan', 'https://evil.test')).toBeNull();
    expect(preflightHeaders(ORIGINS, '/oauth/strava/token', APP)).toBeNull();
  });
  it('keeps an existing Vary when stamping a response', () => {
    const res = new Response(null, { headers: { vary: 'Accept-Encoding' } });
    applyCors(res, ORIGINS, '/share', APP);
    expect(res.headers.get('vary')).toBe('Accept-Encoding, Origin');
    expect(res.headers.get('access-control-expose-headers')).toContain('Retry-After');
  });
});

describe('proxy CORS', () => {
  it('answers an allowed preflight with 204', async () => {
    await withEnv({}, async () => {
      const res = await proxy(
        req(`${API}/weather/radar/dpc/frames`, 'OPTIONS', {
          origin: APP,
          'access-control-request-method': 'GET',
        }),
      );
      expect(res.status).toBe(204);
      expect(res.headers.get('access-control-allow-origin')).toBe(APP);
      expect(res.headers.get('access-control-allow-methods')).toBe('GET, OPTIONS');
      expect(res.headers.get('vary')).toBe('Origin');
      expect(res.headers.get('access-control-allow-credentials')).toBeNull();
    });
  });

  it('answers the planner\'s preflight for POST /plus/web', async () => {
    await withEnv({}, async () => {
      const res = await proxy(
        req(`${API}/plus/web`, 'OPTIONS', {
          origin: APP,
          'access-control-request-method': 'POST',
        }),
      );
      expect(res.status).toBe(204);
      expect(res.headers.get('access-control-allow-methods')).toBe('POST, OPTIONS');
    });
  });

  it('gives a disallowed or missing origin no preflight answer', async () => {
    await withEnv({}, async () => {
      for (const headers of [{ origin: 'https://evil.test' }, {}] as Record<string, string>[]) {
        const res = await proxy(req(`${API}/share`, 'OPTIONS', headers));
        expect(res.status).toBe(404);
        expect(res.headers.get('access-control-allow-origin')).toBeNull();
        expect(res.headers.get('access-control-allow-methods')).toBeNull();
      }
    });
  });

  it('allows a configured dev origin and nothing when disabled', async () => {
    await withEnv({ CORS_ORIGINS: 'http://localhost:5000' }, async () => {
      const ok = await proxy(req(`${API}/share`, 'OPTIONS', { origin: 'http://localhost:5000' }));
      expect(ok.status).toBe(204);
      const no = await proxy(req(`${API}/share`, 'OPTIONS', { origin: APP }));
      expect(no.status).toBe(404);
    });
    await withEnv({ CORS_ORIGINS: ' , ' }, async () => {
      const res = await proxy(req(`${API}/health`, 'GET', { origin: APP }));
      expect(res.headers.get('access-control-allow-origin')).toBeNull();
    });
  });

  it('stamps actual responses, errors included', async () => {
    await withEnv({}, async () => {
      const ok = await proxy(req(`${API}/health`, 'GET', { origin: APP }));
      expect(ok.status).toBe(200);
      expect(ok.headers.get('access-control-allow-origin')).toBe(APP);
      expect(ok.headers.get('vary')).toContain('Origin');
      expect(ok.headers.get('access-control-expose-headers')).toContain('Retry-After');

      // Wrong method on a browser route: the proxy's own JSON 404.
      const wrong = await proxy(req(`${API}/share`, 'GET', { origin: APP }));
      expect(wrong.status).toBe(404);
      expect(wrong.headers.get('access-control-allow-origin')).toBe(APP);

      const post = await proxy(req(`${API}/ai/plan`, 'POST', { origin: APP }));
      expect(post.headers.get('access-control-allow-origin')).toBe(APP);
    });
  });

  it('sends nothing to a disallowed origin or an absent one', async () => {
    await withEnv({}, async () => {
      for (const headers of [{ origin: 'https://evil.test' }, {}] as Record<string, string>[]) {
        const res = await proxy(req(`${API}/health`, 'GET', headers));
        expect(res.headers.get('access-control-allow-origin')).toBeNull();
        expect(res.headers.get('vary')).toBeNull();
      }
    });
  });

  it('keeps oauth and proxy routes phone-only', async () => {
    await withEnv({}, async () => {
      const pre = await proxy(req(`${API}/oauth/strava/token`, 'OPTIONS', { origin: APP }));
      expect(pre.status).toBe(404);
      expect(pre.headers.get('access-control-allow-origin')).toBeNull();
      for (const path of ['/oauth/strava/token', '/proxy/strava/athlete']) {
        const res = await proxy(req(`${API}${path}`, 'POST', { origin: APP }));
        expect(res.headers.get('access-control-allow-origin')).toBeNull();
      }
    });
  });

  it('gives the site host none', async () => {
    await withEnv({}, async () => {
      const res = await proxy(req('https://velorki.com/robots.txt', 'GET', { origin: APP }));
      expect(res.headers.get('access-control-allow-origin')).toBeNull();
      const pre = await proxy(req('https://velorki.com/share', 'OPTIONS', { origin: APP }));
      expect(pre.headers.get('access-control-allow-origin')).toBeNull();
    });
  });
});
