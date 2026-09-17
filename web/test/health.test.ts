// SPDX-License-Identifier: AGPL-3.0-only
import { afterEach, describe, expect, it, vi } from 'vitest';
import { GET, HEAD, resetBrouterCache } from '@/app/(api)/health/route';
import { bodyOf, fetchCall, withEnv } from './helpers';

const URL_HEALTH = 'https://api.velorki.com/health';

afterEach(() => {
  vi.unstubAllGlobals();
  resetBrouterCache();
});

describe('GET /health', () => {
  it('reports unconfigured integrations without calling out', async () => {
    await withEnv({ APP_VERSION: '1.4.2' }, async () => {
      const res = await GET(new Request(URL_HEALTH));
      expect(res.status).toBe(200);
      expect(await res.json()).toEqual({
        status: 'ok',
        version: '1.4.2',
        brouter: 'unconfigured',
        llm: 'unconfigured',
      });
      expect(res.headers.get('cache-control')).toBe('no-store');
    });
  });

  it('defaults the version to "dev" and needs no auth', async () => {
    await withEnv({}, async () => {
      const res = await GET(new Request(URL_HEALTH));
      expect((await bodyOf<{ version: string }>(res)).version).toBe('dev');
      expect(res.headers.get('x-request-id')).toBeTruthy();
    });
  });

  it('answers HEAD with the same status and headers', async () => {
    await withEnv({ APP_VERSION: '2.0.0' }, async () => {
      const res = await HEAD(new Request(URL_HEALTH, { method: 'HEAD' }));
      // The body is deliberately not asserted: Next and undici strip it from a
      // HEAD response on the wire, so no client ever sees the one built here.
      expect(res.status).toBe(200);
      expect(res.headers.get('cache-control')).toBe('no-store');
      expect(res.headers.get('content-type')).toContain('application/json');
      expect(res.headers.get('x-request-id')).toBeTruthy();
    });
  });

  it('probes BRouter and caches the result for 60 s', async () => {
    const fetchMock = vi.fn(async () => new Response('{"type":"FeatureCollection"}', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await withEnv(
      {
        BROUTER_URL: 'http://brouter.internal:17777',
        LLM_BASE_URL: 'http://llm.internal/v1',
        LLM_MODEL: 'x',
      },
      async () => {
        const first = await GET(new Request(URL_HEALTH));
        expect(await first.json()).toMatchObject({ brouter: 'ok', llm: 'configured' });

        const { url } = fetchCall(fetchMock);
        expect(url).toContain('/brouter?lonlats=8.5,47.4');
        expect(url).toContain('profile=trekking');
        expect(url).toContain('format=geojson');

        // Second call must be served from the 60 s cache.
        await GET(new Request(URL_HEALTH));
        expect(fetchMock).toHaveBeenCalledTimes(1);
      },
    );
  });

  it('reports degraded when BRouter fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error('ECONNREFUSED');
      }),
    );
    await withEnv({ BROUTER_URL: 'http://brouter.internal:17777' }, async () => {
      const res = await GET(new Request(URL_HEALTH));
      expect((await bodyOf<{ brouter: string }>(res)).brouter).toBe('degraded');
    });
  });
});

describe('request id contract', () => {
  it('echoes a caller-supplied X-Request-Id', async () => {
    await withEnv({}, async () => {
      const res = await GET(
        new Request(URL_HEALTH, {
          headers: { 'x-request-id': 'trace-abc-123', 'x-velorki-client': 'android/1.0.0+1' },
        }),
      );
      expect(res.headers.get('x-request-id')).toBe('trace-abc-123');
    });
  });

  it('generates an X-Request-Id when the supplied one is malformed', async () => {
    await withEnv({}, async () => {
      const res = await GET(
        new Request(URL_HEALTH, { headers: { 'x-request-id': 'bad id with spaces' } }),
      );
      expect(res.headers.get('x-request-id')).not.toBe('bad id with spaces');
      expect(res.headers.get('x-request-id')).toBeTruthy();
    });
  });
});
