// SPDX-License-Identifier: AGPL-3.0-only
import { mkdtempSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { POST as createShare } from '@/app/(api)/share/route';
import { GET as getGpx } from '@/app/(share)/s/[id]/gpx/route';
import { SHARE_TTL_MS, ShareStore, isValidShareId, randomId } from '@/share/store';
import { gpxFilename, shareKindLabel, shareStats, shareTitle } from '@/share/format';
import { AUTH, bodyOf, errOf, jsonRequest, sampleGpx, type ShareCreated, withEnv } from './helpers';

const SHARE_URL = 'https://api.velorki.com/share';

function shareBody(extra: Record<string, unknown> = {}) {
  return {
    kind: 'route',
    name: 'Uetliberg loop',
    gpx: sampleGpx(5),
    summary: { distance_km: 42.4, ascent_m: 730, duration_s: 7200 },
    ...extra,
  };
}

function create(
  extra: Record<string, unknown> = {},
  headers: Record<string, string> = AUTH,
): Promise<Response> {
  return createShare(jsonRequest(SHARE_URL, shareBody(extra), headers));
}

function gpxRequest(id: string): Promise<Response> {
  return getGpx(new Request(`https://velorki.com/s/${id}/gpx`), {
    params: Promise.resolve({ id }),
  });
}

describe('POST /share', () => {
  it('stores the share and returns an id and a public URL', async () => {
    await withEnv({}, async () => {
      const res = await create();
      expect(res.status).toBe(201);
      const body = await bodyOf<ShareCreated>(res);
      expect(body.id).toMatch(/^[A-Za-z0-9]{10}$/);
      expect(body.url).toBe(`https://share.velorki.test/s/${body.id}`);
      expect(res.headers.get('cache-control')).toBe('no-store');
    });
  });

  it('requires entitlement', async () => {
    await withEnv({ REVENUECAT_MODE: 'live', REVENUECAT_SECRET_KEY: 'sk' }, async () => {
      const res = await createShare(jsonRequest(SHARE_URL, shareBody()));
      expect(res.status).toBe(401);
    });
  });

  it('rejects bad bodies', async () => {
    await withEnv({}, async () => {
      for (const extra of [
        { kind: 'segment' },
        { name: '' },
        { gpx: 'this is not gpx' },
        { summary: {} },
        // > 2 MB of GPX
        { gpx: `<gpx>${'x'.repeat(2 * 1024 * 1024)}</gpx>` },
      ]) {
        const res = await create(extra);
        expect(res.status, JSON.stringify(Object.keys(extra))).toBe(400);
        expect((await errOf(res)).code).toBe('invalid_request');
      }
    });
  });

  it('rate limits at 30 shares per day per user', async () => {
    await withEnv({}, async () => {
      for (let i = 0; i < 30; i += 1) {
        expect((await create()).status, `share ${String(i)}`).toBe(201);
      }
      const limited = await create();
      expect(limited.status).toBe(429);
      expect((await errOf(limited)).retry_after_s).toBeGreaterThan(0);

      // A different rider has their own bucket.
      const other = await create({}, { authorization: 'Bearer someone-else' });
      expect(other.status).toBe(201);
    });
  });

  it('charges the per-IP limit before the body is read', async () => {
    await withEnv({ TRUST_PROXY: '1', CLIENT_IP_HEADER: 'cf-connecting-ip' }, async () => {
      // One address, a different rider each time, so only the per-IP window
      // fills up. The body is one the schema would reject with 400.
      const bad = (rider: number) =>
        create(
          { kind: 'segment' },
          { authorization: `Bearer rider-${String(rider)}`, 'cf-connecting-ip': '203.0.113.9' },
        );

      for (let i = 0; i < 60; i += 1) {
        expect((await bad(i)).status, `call ${String(i)}`).toBe(400);
      }
      // Over the limit the same body answers 429: the request is refused
      // before anything is read, so it never gets as far as being invalid.
      const limited = await bad(60);
      expect(limited.status).toBe(429);
      expect((await errOf(limited)).code).toBe('rate_limited');

      // Another address still has its whole window.
      const other = await create({ kind: 'segment' }, { ...AUTH, 'cf-connecting-ip': '198.51.100.1' });
      expect(other.status).toBe(400);
    });
  });
});

describe('GET /s/<id>.gpx', () => {
  it('serves the GPX unchanged with the right content type', async () => {
    await withEnv({}, async () => {
      const gpx = sampleGpx(7);
      const created = await create({ gpx });
      const { id } = await bodyOf<ShareCreated>(created);

      const res = await gpxRequest(id);
      expect(res.status).toBe(200);
      expect(res.headers.get('content-type')).toBe('application/gpx+xml; charset=utf-8');
      expect(res.headers.get('cache-control')).toBe('public, max-age=3600');
      expect(res.headers.get('content-disposition')).toBe(
        'attachment; filename="Uetliberg-loop.gpx"',
      );
      expect(await res.text()).toBe(gpx);
    });
  });

  it('needs no authentication', async () => {
    await withEnv({}, async () => {
      const { id } = await bodyOf<ShareCreated>(await create());
      expect((await gpxRequest(id)).status).toBe(200);
    });
  });

  it('404s with the JSON body on unknown and malformed ids', async () => {
    await withEnv({}, async () => {
      for (const id of ['aaaaaaaaaa', 'short', 'way-too-long-id', 'bad!chars', 'nope']) {
        const res = await gpxRequest(id);
        expect(res.status, id).toBe(404);
        expect((await errOf(res)).code).toBe('not_found');
      }
    });
  });

  it('derives an ASCII filename from the share name', () => {
    expect(gpxFilename('', 'AbCdEf0123')).toBe('velorki-AbCdEf0123.gpx');
    expect(gpxFilename('Tour de Suisse', 'AbCdEf0123')).toBe('Tour-de-Suisse.gpx');
    expect(gpxFilename('Zürich / Üetliberg!', 'AbCdEf0123')).toBe('Zurich-Uetliberg.gpx');
  });
});

describe('the share page content', () => {
  it('formats the stats the way the relay page did', async () => {
    await withEnv({}, async (ctx) => {
      const { id } = await bodyOf<ShareCreated>(await create());
      const record = ctx.store.get(id);
      expect(record).not.toBeNull();
      if (record === null) return;

      expect(shareKindLabel(record)).toBe('Route');
      expect(shareTitle(record)).toBe('Uetliberg loop');
      expect(shareStats(record)).toEqual([
        { label: 'Distance', value: '42.4 km' },
        { label: 'Ascent', value: '730 m' },
        { label: 'Duration', value: '2 h 00 min' },
      ]);
    });
  });

  it('omits the stats the summary does not carry', async () => {
    await withEnv({}, async (ctx) => {
      const { id } = await bodyOf<ShareCreated>(await create({ summary: { distance_km: 10 } }));
      const record = ctx.store.get(id);
      expect(record).not.toBeNull();
      if (record === null) return;
      expect(shareStats(record)).toEqual([{ label: 'Distance', value: '10.0 km' }]);
    });
  });

  it('falls back to a generic title for a nameless ride', () => {
    const record = {
      id: 'AbCdEf0123',
      kind: 'ride' as const,
      name: '',
      gpx: '<gpx/>',
      summary: { distance_km: 0, duration_s: 90 },
      createdAt: 0,
      expiresAt: 1,
    };
    expect(shareTitle(record)).toBe('Velorki route');
    expect(shareKindLabel(record)).toBe('Ride');
    expect(shareStats(record)).toEqual([
      { label: 'Distance', value: '0.0 km' },
      { label: 'Duration', value: '1 min' },
    ]);
  });
});

describe('expiry', () => {
  it('404s once the share has expired', async () => {
    let now = Date.UTC(2026, 0, 1);
    const store = new ShareStore(':memory:', () => now);

    await withEnv(
      {},
      async () => {
        const { id } = await bodyOf<ShareCreated>(await create());
        expect(store.get(id)).not.toBeNull();

        // One day before expiry: still there.
        now += SHARE_TTL_MS - 86_400_000;
        expect(store.get(id)).not.toBeNull();
        expect((await gpxRequest(id)).status).toBe(200);

        // One second after expiry: gone, for both the page and the GPX.
        now += 86_400_000 + 1000;
        expect(store.get(id)).toBeNull();
        expect((await gpxRequest(id)).status).toBe(404);
      },
      { store, now: () => now },
    );

    store.close();
  });
});

describe('share store', () => {
  it('sweeps the expired rows and leaves the live ones', () => {
    let now = Date.UTC(2026, 0, 1);
    const store = new ShareStore(':memory:', () => now);

    const drop = store.create({
      kind: 'route',
      name: 'a',
      gpx: '<gpx/>',
      summary: { distance_km: 1 },
    });
    // Half a life later, so the two rows do not expire in the same sweep.
    now += SHARE_TTL_MS / 2;
    const keep = store.create({
      kind: 'ride',
      name: 'b',
      gpx: '<gpx/>',
      summary: { distance_km: 2 },
    });

    expect(store.sweep()).toBe(0);

    // Past the first row's year, with half a year left on the second.
    now += SHARE_TTL_MS / 2 + 1;
    expect(store.sweep()).toBe(1);
    expect(store.get(drop.id)).toBeNull();
    expect(store.get(keep.id)).not.toBeNull();

    now += SHARE_TTL_MS / 2;
    expect(store.sweep()).toBe(1);
    expect(store.get(keep.id)).toBeNull();
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

  it('keeps an on-disk database at 0600, wal and shm included', () => {
    const dir = mkdtempSync(join(tmpdir(), 'velorki-share-'));
    const path = join(dir, 'nested', 'share.sqlite');
    const store = new ShareStore(path);
    // A write forces WAL to materialise the -wal and -shm siblings.
    store.create({ kind: 'route', name: 'n', gpx: '<gpx/>', summary: { distance_km: 1 } });

    for (const file of [path, `${path}-wal`, `${path}-shm`]) {
      expect(statSync(file).mode & 0o777, file).toBe(0o600);
    }

    store.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('generates 10-character base62 ids', () => {
    const ids = new Set(Array.from({ length: 500 }, () => randomId()));
    expect(ids.size).toBe(500);
    for (const id of ids) expect(isValidShareId(id)).toBe(true);
    expect(isValidShareId('short')).toBe(false);
    expect(isValidShareId('has-dash-x')).toBe(false);
  });
});
