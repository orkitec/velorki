// SPDX-License-Identifier: AGPL-3.0-only
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  bodyOf,
  errOf,
  fetchCall,
  testApp,
} from './helpers.js';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('GET /health', () => {
  it('reports unconfigured integrations without calling out', async () => {
    const app = testApp({ env: { APP_VERSION: '1.4.2' } });
    const res = await app.inject({ method: 'GET', url: '/health' });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      status: 'ok',
      version: '1.4.2',
      brouter: 'unconfigured',
      llm: 'unconfigured',
    });
    await app.close();
  });

  it('defaults the version to "dev" and needs no auth', async () => {
    const app = testApp();
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(bodyOf<{ version: string }>(res).version).toBe('dev');
    expect(res.headers['x-request-id']).toBeTruthy();
    await app.close();
  });

  it('probes BRouter and caches the result for 60 s', async () => {
    const fetchMock = vi.fn(async () => new Response('{"type":"FeatureCollection"}', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    const app = testApp({
      env: { BROUTER_URL: 'http://brouter.internal:17777', LLM_BASE_URL: 'http://llm.internal/v1', LLM_MODEL: 'x' },
    });

    const first = await app.inject({ method: 'GET', url: '/health' });
    expect(first.json()).toMatchObject({ brouter: 'ok', llm: 'configured' });

    const { url } = fetchCall(fetchMock);
    expect(url).toContain('/brouter?lonlats=8.5,47.4');
    expect(url).toContain('profile=trekking');
    expect(url).toContain('format=geojson');

    // Second call must be served from the 60 s cache.
    await app.inject({ method: 'GET', url: '/health' });
    expect(fetchMock).toHaveBeenCalledTimes(1);

    await app.close();
  });

  it('reports degraded when BRouter fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error('ECONNREFUSED');
      }),
    );
    const app = testApp({ env: { BROUTER_URL: 'http://brouter.internal:17777' } });
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(bodyOf<{ brouter: string }>(res).brouter).toBe('degraded');
    await app.close();
  });
});

describe('error contract', () => {
  it('returns the uniform body for unknown routes', async () => {
    const app = testApp();
    const res = await app.inject({ method: 'GET', url: '/nope' });
    expect(res.statusCode).toBe(404);
    expect(errOf(res).code).toBe('not_found');
    expect(typeof errOf(res).message).toBe('string');
    await app.close();
  });

  it('echoes a caller-supplied X-Request-Id', async () => {
    const app = testApp();
    const res = await app.inject({
      method: 'GET',
      url: '/health',
      headers: { 'x-request-id': 'trace-abc-123', 'x-velorki-client': 'android/1.0.0+1' },
    });
    expect(res.headers['x-request-id']).toBe('trace-abc-123');
    await app.close();
  });

  it('generates an X-Request-Id when the supplied one is malformed', async () => {
    const app = testApp();
    const res = await app.inject({
      method: 'GET',
      url: '/health',
      headers: { 'x-request-id': 'bad id with spaces' },
    });
    expect(res.headers['x-request-id']).not.toBe('bad id with spaces');
    await app.close();
  });
});
