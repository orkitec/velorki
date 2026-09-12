// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import {
  AUTH,
  bodyOf,
  type ShareCreated,
  errOf,
  sampleGpx,
  testApp,
} from './helpers.js';
import { SHARE_TTL_MS, ShareStore, isValidShareId, randomId } from '../src/share/store.js';

function shareBody(extra: Record<string, unknown> = {}) {
  return {
    kind: 'route',
    name: 'Uetliberg loop',
    gpx: sampleGpx(5),
    summary: { distance_km: 42.4, ascent_m: 730, duration_s: 7200 },
    ...extra,
  };
}

describe('POST /share', () => {
  it('stores the share and returns an id and a public URL', async () => {
    const app = testApp();
    const res = await app.inject({
      method: 'POST',
      url: '/share',
      headers: AUTH,
      payload: shareBody(),
    });

    expect(res.statusCode).toBe(201);
    const body = bodyOf<ShareCreated>(res);
    expect(body.id).toMatch(/^[A-Za-z0-9]{10}$/);
    expect(body.url).toBe(`https://share.velorki.test/s/${body.id}`);
    await app.close();
  });

  it('requires entitlement', async () => {
    const app = testApp({ env: { REVENUECAT_MODE: 'live', REVENUECAT_SECRET_KEY: 'sk' } });
    const res = await app.inject({ method: 'POST', url: '/share', payload: shareBody() });
    expect(res.statusCode).toBe(401);
    await app.close();
  });

  it('rejects bad bodies', async () => {
    const app = testApp();
    for (const payload of [
      shareBody({ kind: 'segment' }),
      shareBody({ name: '' }),
      shareBody({ gpx: 'this is not gpx' }),
      shareBody({ summary: {} }),
      // > 2 MB of GPX
      shareBody({ gpx: `<gpx>${'x'.repeat(2 * 1024 * 1024)}</gpx>` }),
    ]) {
      const res = await app.inject({ method: 'POST', url: '/share', headers: AUTH, payload });
      expect(res.statusCode).toBe(400);
      expect(errOf(res).code).toBe('invalid_request');
    }
    await app.close();
  });

  it('rate limits at 30 shares per day per user', async () => {
    const app = testApp();
    for (let i = 0; i < 30; i += 1) {
      const res = await app.inject({
        method: 'POST',
        url: '/share',
        headers: AUTH,
        payload: shareBody(),
      });
      expect(res.statusCode, `share ${String(i)}`).toBe(201);
    }
    const limited = await app.inject({
      method: 'POST',
      url: '/share',
      headers: AUTH,
      payload: shareBody(),
    });
    expect(limited.statusCode).toBe(429);
    expect(errOf(limited).retry_after_s).toBeGreaterThan(0);

    // A different rider has their own bucket.
    const other = await app.inject({
      method: 'POST',
      url: '/share',
      headers: { authorization: 'Bearer someone-else' },
      payload: shareBody(),
    });
    expect(other.statusCode).toBe(201);
    await app.close();
  });
});

describe('GET /s/:id', () => {
  it('renders a self-contained page with the name and stats', async () => {
    const app = testApp();
    const created = await app.inject({
      method: 'POST',
      url: '/share',
      headers: AUTH,
      payload: shareBody(),
    });
    const { id } = bodyOf<ShareCreated>(created);

    const page = await app.inject({ method: 'GET', url: `/s/${id}` });
    expect(page.statusCode).toBe(200);
    expect(page.headers['content-type']).toContain('text/html');
    expect(page.payload).toContain('Uetliberg loop');
    expect(page.payload).toContain('42.4 km');
    expect(page.payload).toContain('730 m');
    expect(page.payload).toContain('2 h 00 min');
    expect(page.payload).toContain(`velorki://share/${id}`);
    expect(page.payload).toContain(`/s/${id}.gpx`);
    expect(page.payload).toContain('https://tiles.openfreemap.org/styles/liberty');
    // Pinned MapLibre, and nothing else external.
    expect(page.payload).toMatch(/unpkg\.com\/maplibre-gl@\d+\.\d+\.\d+\//);
    const externalHosts = [...page.payload.matchAll(/https:\/\/([\w.-]+)/g)].map((m) => m[1]);
    for (const host of new Set(externalHosts)) {
      expect(
        ['unpkg.com', 'tiles.openfreemap.org', 'www.openstreetmap.org'].includes(host ?? ''),
        `unexpected external host ${String(host)}`,
      ).toBe(true);
    }
    await app.close();
  });

  it('escapes the share name', async () => {
    const app = testApp();
    const created = await app.inject({
      method: 'POST',
      url: '/share',
      headers: AUTH,
      payload: shareBody({ name: '<script>alert(1)</script>' }),
    });
    const page = await app.inject({ method: 'GET', url: `/s/${bodyOf<ShareCreated>(created).id}` });
    expect(page.payload).not.toContain('<script>alert(1)</script>');
    expect(page.payload).toContain('&lt;script&gt;');
    await app.close();
  });

  it('serves the GPX unchanged with the right content type', async () => {
    const app = testApp();
    const gpx = sampleGpx(7);
    const created = await app.inject({
      method: 'POST',
      url: '/share',
      headers: AUTH,
      payload: shareBody({ gpx }),
    });
    const { id } = bodyOf<ShareCreated>(created);

    const res = await app.inject({ method: 'GET', url: `/s/${id}.gpx` });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('application/gpx+xml');
    expect(res.payload).toBe(gpx);
    await app.close();
  });

  it('needs no authentication', async () => {
    const app = testApp();
    const created = await app.inject({
      method: 'POST',
      url: '/share',
      headers: AUTH,
      payload: shareBody(),
    });
    const res = await app.inject({ method: 'GET', url: `/s/${bodyOf<ShareCreated>(created).id}` });
    expect(res.statusCode).toBe(200);
    await app.close();
  });

  it('404s on unknown and malformed ids', async () => {
    const app = testApp();
    for (const url of ['/s/aaaaaaaaaa', '/s/short', '/s/way-too-long-id', '/s/bad!chars', '/s/nope.gpx']) {
      const res = await app.inject({ method: 'GET', url });
      expect(res.statusCode, url).toBe(404);
      expect(errOf(res).code).toBe('not_found');
    }
    await app.close();
  });

  it('404s once the share has expired', async () => {
    let now = Date.UTC(2026, 0, 1);
    const store = new ShareStore(':memory:', () => now);
    const app = testApp({ shares: store });

    const created = await app.inject({
      method: 'POST',
      url: '/share',
      headers: AUTH,
      payload: shareBody(),
    });
    const { id } = bodyOf<ShareCreated>(created);

    // One day before expiry: still there.
    now += SHARE_TTL_MS - 86_400_000;
    expect((await app.inject({ method: 'GET', url: `/s/${id}` })).statusCode).toBe(200);

    // One second after expiry: gone, for both the page and the GPX.
    now += 86_400_000 + 1000;
    expect((await app.inject({ method: 'GET', url: `/s/${id}` })).statusCode).toBe(404);
    expect((await app.inject({ method: 'GET', url: `/s/${id}.gpx` })).statusCode).toBe(404);

    await app.close();
    store.close();
  });
});

describe('share store', () => {
  it('sweeps expired rows', () => {
    let now = Date.UTC(2026, 0, 1);
    const store = new ShareStore(':memory:', () => now);

    const keep = store.create({ kind: 'route', name: 'a', gpx: '<gpx/>', summary: { distance_km: 1 } });
    now += 1000;
    const drop = store.create({ kind: 'ride', name: 'b', gpx: '<gpx/>', summary: { distance_km: 2 } });

    expect(store.sweep()).toBe(0);

    now += SHARE_TTL_MS + 1;
    expect(store.sweep()).toBe(2);
    expect(store.get(keep.id)).toBeNull();
    expect(store.get(drop.id)).toBeNull();
    store.close();
  });

  it('round-trips the summary', () => {
    const store = new ShareStore(':memory:');
    const summary = { distance_km: 12.5, ascent_m: 300, duration_s: 3600 };
    const created = store.create({ kind: 'ride', name: 'n', gpx: '<gpx/>', summary });
    expect(store.get(created.id)?.summary).toEqual(summary);
    expect(store.get(created.id)?.kind).toBe('ride');
    store.close();
  });

  it('generates 10-character base62 ids', () => {
    const ids = new Set(Array.from({ length: 500 }, () => randomId()));
    expect(ids.size).toBe(500);
    for (const id of ids) expect(isValidShareId(id)).toBe(true);
    expect(isValidShareId('short')).toBe(false);
    expect(isValidShareId('has-dash-x')).toBe(false);
  });
});
