// SPDX-License-Identifier: AGPL-3.0-only
import { inflateSync } from 'node:zlib';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as frames } from '@/app/(api)/weather/radar/dpc/frames/route';
import { GET as image } from '@/app/(api)/weather/radar/dpc/image/route';
import { GET as operaFrames } from '@/app/(api)/weather/radar/opera/frames/route';
import { MemoryCounters } from '@/server/counters';
import { CLASS_DRY, CLASS_NO_DATA, classOfRate } from '@/weather/radar/classes';
import { DPC_GRID_FORMAT, DPC_GRID_VERSION, decodeDpcTiff } from '@/weather/dpc/grid';
import {
  DPC_API,
  DpcStore,
  dpcKey,
  dpcStamp,
  frameLink,
  parseLastProduct,
} from '@/weather/dpc/store';
import { Tmerc } from '@/weather/dpc/tmerc';
import { parseGrid, serialiseGrid } from '@/weather/radar/grid';
import { PALETTE_NO_DATA, classesOfArea, mercatorOf, type MercatorBox } from '@/weather/radar/render';
import { MAX_SHARED_BYTES } from '@/weather/radar/store';
import { OPERA_BUCKET } from '@/weather/opera/store';
import { AUTH, bodyOf, errOf, withEnv } from './helpers';
import { DPC_FIXTURE, dpcFixtureTiff } from './dpc/fixture';

const NOW = Date.parse('2026-10-12T21:07:30Z');
const NEWEST = Date.parse('2026-10-12T21:00:00Z');
const FRAMES_URL = 'https://api.velorki.com/weather/radar/dpc/frames';
const IMAGE_URL = 'https://api.velorki.com/weather/radar/dpc/image';
const BUCKET = 'https://s3-prod-dpc-radar.s3.eu-south-1.amazonaws.com';
const LAST_URL = `${DPC_API}/findLastProductByType?type=SRI`;
const DOWNLOAD_URL = `${DPC_API}/downloadProduct`;

/** A box of `km` around a point, in Web Mercator. */
function boxAround(lat: number, lon: number, km: number): MercatorBox {
  const [x, y] = mercatorOf(lon, lat);
  const half = (km * 1000) / Math.cos((lat * Math.PI) / 180) / 2;
  return [x - half, y - half, x + half, y + half];
}

/** The palette indices of an indexed PNG, row by row. */
function pngIndices(png: Uint8Array): { width: number; height: number; px: Uint8Array } {
  const buf = Buffer.from(png);
  let at = 8;
  let width = 0;
  let height = 0;
  const idat: Buffer[] = [];
  while (at < buf.length) {
    const len = buf.readUInt32BE(at);
    const type = buf.toString('ascii', at + 4, at + 8);
    const data = buf.subarray(at + 8, at + 8 + len);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
    }
    if (type === 'IDAT') idat.push(data);
    at += 12 + len;
  }
  const raw = inflateSync(Buffer.concat(idat));
  const px = new Uint8Array(width * height);
  for (let y = 0; y < height; y += 1) {
    px.set(raw.subarray(y * (width + 1) + 1, (y + 1) * (width + 1)), y * width);
  }
  return { width, height, px };
}

/** The pre-signed link the API answers for the SRI at `time`. */
function signedLink(time: number, host = BUCKET): string {
  return (
    `${host}/${dpcKey(time)}?response-content-disposition=attachment` +
    '&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Expires=300&X-Amz-Signature=abc'
  );
}

interface Call {
  url: string;
  method: string;
  headers: Headers;
  body?: string;
}

/**
 * The DPC's API and bucket: `findLastProductByType` names [newest], and
 * `downloadProduct` links to the fixture for any time ([link] to change
 * the answer).
 */
function stubDpc(
  opts: {
    newest?: number;
    last?: () => Response;
    link?: (time: number) => unknown;
    tiff?: () => Response;
    revenueCat?: () => Response;
  } = {},
) {
  const calls: Call[] = [];
  const fetchMock = vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    const call: Call = {
      url,
      method: init?.method ?? 'GET',
      headers: new Headers(init?.headers),
      ...(typeof init?.body === 'string' ? { body: init.body } : {}),
    };
    calls.push(call);
    if (url.startsWith('https://api.revenuecat.com/')) {
      return opts.revenueCat?.() ?? new Response('{}', { status: 404 });
    }
    if (url === LAST_URL) {
      return (
        opts.last?.() ??
        Response.json({
          total: 1,
          lastProducts: [{ productType: 'SRI', time: opts.newest ?? NEWEST, period: 'PT5M' }],
        })
      );
    }
    if (url === DOWNLOAD_URL && call.method === 'POST') {
      const { productDate } = JSON.parse(call.body ?? '{}') as { productDate: number };
      const answer = opts.link?.(productDate) ?? {
        bucket: 's3-prod-dpc-radar',
        key: dpcKey(productDate),
        url: signedLink(productDate),
        expiresSeconds: 300,
      };
      return Response.json(answer);
    }
    if (url.startsWith(`${BUCKET}/SRI/`)) {
      return opts.tiff?.() ?? new Response(Buffer.from(dpcFixtureTiff()), { status: 200 });
    }
    if (url.startsWith(OPERA_BUCKET)) {
      return new Response('<ListBucketResult></ListBucketResult>', { status: 200 });
    }
    throw new Error(`unexpected fetch ${url}`);
  });
  vi.stubGlobal('fetch', fetchMock);
  return calls;
}

const tiffs = (calls: Call[]) => calls.filter((c) => c.url.includes('.tif'));
const downloads = (calls: Call[]) => calls.filter((c) => c.url === DOWNLOAD_URL);

function imageQuery(params: Record<string, string>): Request {
  const url = new URL(IMAGE_URL);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  return new Request(url, { headers: AUTH });
}

const ROME_BOX = boxAround(DPC_FIXTURE.rome.lat, DPC_FIXTURE.rome.lon, 5);
const goodQuery = {
  time: new Date(NEWEST).toISOString(),
  bbox: ROME_BOX.join(','),
  width: '5',
  height: '5',
};

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe('DPC: projection and decoding', () => {
  it('projects the EPSG guidance note’s example to the centimetre', () => {
    // EPSG Guidance Note 7-2, method 9807 (OSGB 1936 / British National Grid).
    const tm = new Tmerc({
      lat0: 49,
      lon0: -2,
      k0: 0.9996012717,
      falseEasting: 400_000,
      falseNorthing: -100_000,
      a: 6_377_563.396,
      invFlattening: 299.3249646,
    });
    const p = tm.forward(50.5, 0.5);
    expect(p.x).toBeCloseTo(577_274.99, 1);
    expect(p.y).toBeCloseTo(69_740.5, 1);
  });

  it('reads the projection from the GeoKeys and classes the rates as they are', async () => {
    const grid = await decodeDpcTiff(dpcFixtureTiff());
    expect(grid.proj).toEqual({
      lat0: 42,
      lon0: 12.5,
      k0: 1,
      falseEasting: 0,
      falseNorthing: 0,
      a: 6_378_137,
      invFlattening: 298.257223563,
    });
    expect([grid.width, grid.height, grid.x0, grid.y0, grid.dx, grid.dy]).toEqual([
      20, 20, DPC_FIXTURE.x0, DPC_FIXTURE.y0, 1000, 1000,
    ]);
    const at = (col: number, row: number) => grid.cells[row * grid.width + col];
    expect(at(DPC_FIXTURE.rome.col, DPC_FIXTURE.rome.row)).toBe(9);
    expect(classOfRate(12)).toBe(9);
    expect(at(DPC_FIXTURE.rome.col + 2, DPC_FIXTURE.rome.row - 2)).toBe(3);
    expect(at(DPC_FIXTURE.weak.col, DPC_FIXTURE.weak.row)).toBe(CLASS_DRY);
    expect(at(0, 0)).toBe(CLASS_DRY);
    expect(at(5, DPC_FIXTURE.noDataFromRow)).toBe(CLASS_NO_DATA);
    // No clutter filter: a uniformly heavy band and a lone cell stay.
    expect(at(DPC_FIXTURE.band.fromCol + 2, DPC_FIXTURE.band.row)).toBe(classOfRate(40));
    expect(at(DPC_FIXTURE.speck.col, DPC_FIXTURE.speck.row)).toBe(3);

    const back = await parseGrid(await serialiseGrid(grid, DPC_GRID_FORMAT), DPC_GRID_FORMAT);
    expect(back).toEqual(grid);
    // An OPERA grid's bytes are not a DPC grid.
    await expect(
      parseGrid(await serialiseGrid(grid, 'velorki-opera-grid-2'), DPC_GRID_FORMAT),
    ).rejects.toThrow();
  });

  it('refuses a GeoTIFF in another projection', async () => {
    const buf = Buffer.from(dpcFixtureTiff());
    // GeoKey 3075 (ProjCoordTransGeoKey) = 1 -> 10 (Lambert Azimuthal Equal Area).
    const big = buf.toString('ascii', 0, 2) === 'MM';
    const entry = big ? [0x0c, 0x03, 0, 0, 0, 1, 0, 1] : [0x03, 0x0c, 0, 0, 1, 0, 1, 0];
    const at = buf.indexOf(Buffer.from(entry));
    expect(at).toBeGreaterThan(0);
    buf[at + (big ? 7 : 6)] = 10;
    await expect(decodeDpcTiff(new Uint8Array(buf))).rejects.toThrow(/Transverse Mercator/);
  });

  it('puts a known place on its cell: Rome on the rain, south of it no data', async () => {
    const grid = await decodeDpcTiff(dpcFixtureTiff());
    const tm = new Tmerc(grid.proj);
    const one = (lat: number, lon: number) => classesOfArea(grid, tm, boxAround(lat, lon, 0.2), 1, 1)[0];
    const { lat, lon } = DPC_FIXTURE.rome;
    expect(one(lat, lon)).toBe(9);
    // A kilometre and a half east is the next cell: the shower's light rim.
    expect(one(lat, lon + 0.02)).toBe(3);
    // Five kilometres east, past the rim: dry, transparent.
    expect(one(lat, lon + 0.07)).toBe(0);
    // Ten kilometres south lies in the rows of no data.
    expect(one(lat - 0.09, lon)).toBe(PALETTE_NO_DATA);
    // Far off the grid: transparent.
    expect(one(45, 7)).toBe(0);
  });
});

describe('DPC: the API', () => {
  it('names files by their UTC time', () => {
    expect(dpcStamp(Date.parse('2026-10-13T02:40:00Z'))).toBe('13-10-2026-02-40');
    expect(dpcKey(Date.parse('2026-01-05T07:05:00Z'))).toBe('SRI/05-01-2026-07-05.tif');
  });

  it('reads the newest SRI and nothing else', () => {
    const answer = (products: unknown) => ({ total: 1, lastProducts: products });
    expect(parseLastProduct(answer([{ productType: 'SRI', time: NEWEST, period: 'PT5M' }]))).toBe(
      NEWEST,
    );
    for (const bad of [
      answer([{ productType: 'VMI', time: NEWEST }]),
      answer([{ productType: 'SRI', time: NEWEST + 1 }]),
      answer([{ productType: 'SRI', time: String(NEWEST) }]),
      answer([]),
      { total: 0, lastProducts: [] },
      null,
      'SRI',
    ]) {
      expect(() => parseLastProduct(bad), JSON.stringify(bad)).toThrow();
    }
  });

  it('follows a link only to the file asked for, on a DPC radar bucket', () => {
    const ok = (url: string, key = dpcKey(NEWEST)) => frameLink({ key, url }, NEWEST);
    expect(ok(signedLink(NEWEST))).toBe(new URL(signedLink(NEWEST)).toString());
    expect(ok(signedLink(NEWEST, 'https://dpc-radar.s3.eu-south-1.amazonaws.com'))).toContain(
      'dpc-radar.s3',
    );
    for (const url of [
      signedLink(NEWEST, 'https://evil.example'),
      signedLink(NEWEST, 'https://s3-prod-dpc-radar.s3.eu-south-1.amazonaws.com.evil.example'),
      signedLink(NEWEST, 'https://other-bucket.s3.eu-south-1.amazonaws.com'),
      signedLink(NEWEST, 'https://s3-prod-dpc-radar.s3.us-east-1.amazonaws.com'),
      signedLink(NEWEST, 'http://s3-prod-dpc-radar.s3.eu-south-1.amazonaws.com'),
      signedLink(NEWEST, 'https://s3-prod-dpc-radar.s3.eu-south-1.amazonaws.com:8443'),
      signedLink(NEWEST, 'https://user:pw@s3-prod-dpc-radar.s3.eu-south-1.amazonaws.com'),
      signedLink(NEWEST - 300_000),
      `${BUCKET}/SRI/../VMI/${dpcStamp(NEWEST)}.tif`,
      'not a url',
    ]) {
      expect(() => ok(url), url).toThrow();
    }
    // The key has to be that of the time asked for, too.
    expect(() => ok(signedLink(NEWEST), dpcKey(NEWEST - 300_000))).toThrow();
    expect(() => frameLink({ key: dpcKey(NEWEST) }, NEWEST)).toThrow();
  });
});

describe('DPC: the store', () => {
  it('lists two hours back from the newest the API names, asking once', async () => {
    const calls = stubDpc();
    const store = new DpcStore({ counters: new MemoryCounters(), userAgent: 'test' });
    const got = await store.frames();
    expect(got.at(-1)).toBe(NEWEST);
    expect(got[0]).toBe(Date.parse('2026-10-12T19:10:00Z'));
    expect(got).toHaveLength(23);
    expect(got.every((t, i) => i === 0 || t - (got[i - 1] ?? 0) === 300_000)).toBe(true);
    await store.frames();
    expect(calls.map((c) => c.url)).toEqual([LAST_URL]);
    // With the site's origin, as the API asks, and the relay's user agent.
    expect(calls[0]?.headers.get('origin')).toBe('https://velorki.com');
    expect(calls[0]?.headers.get('user-agent')).toBe('test');
  });

  it('never lists a frame past the clock', async () => {
    stubDpc({ newest: NOW + 3_600_000 - (NOW % 300_000) });
    const store = new DpcStore({ counters: new MemoryCounters(), userAgent: 'test' });
    expect((await store.frames()).at(-1)).toBe(Date.parse('2026-10-12T21:05:00Z'));
  });

  it('fetches a frame once, for concurrent requests and for another worker', async () => {
    const calls = stubDpc();
    const counters = new MemoryCounters();
    const store = new DpcStore({ counters, userAgent: 'test' });
    await Promise.all([
      store.image(NEWEST, ROME_BOX, 5, 5),
      store.image(NEWEST, ROME_BOX, 5, 5),
      store.grid(NEWEST),
    ]);
    expect(downloads(calls)).toHaveLength(1);
    expect(JSON.parse(downloads(calls)[0]?.body ?? '{}')).toEqual({
      productType: 'SRI',
      productDate: NEWEST,
    });
    expect(downloads(calls)[0]?.headers.get('origin')).toBe('https://velorki.com');
    expect(tiffs(calls).map((c) => c.url)).toEqual([new URL(signedLink(NEWEST)).toString()]);
    const key = store.gridKey(NEWEST);
    expect(key).toBe(`dpc:grid:v${String(DPC_GRID_VERSION)}:${dpcStamp(NEWEST)}`);
    const shared = await counters.get<Uint8Array>(key);
    expect(shared).toBeInstanceOf(Uint8Array);
    expect(shared?.length).toBeLessThan(MAX_SHARED_BYTES);
    // Another worker: the same shared cache, its own memory.
    const other = new DpcStore({ counters, userAgent: 'test' });
    expect(await other.grid(NEWEST)).toEqual(await store.grid(NEWEST));
    expect(downloads(calls)).toHaveLength(1);
  });

  it('waits for the worker that fetches, instead of fetching too', async () => {
    let release: () => void = () => undefined;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    const calls = stubDpc();
    const counters = new MemoryCounters();
    const slow = vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
      await gate;
      return fetch(input, init);
    });
    const first = new DpcStore({ counters, userAgent: 'test', fetch: slow });
    const second = new DpcStore({ counters, userAgent: 'test' });
    const a = first.grid(NEWEST);
    await vi.waitFor(() => expect(slow).toHaveBeenCalled());
    const b = second.grid(NEWEST);
    release();
    expect(await b).toEqual(await a);
    expect(tiffs(calls)).toHaveLength(1);
  });

  it('follows no link off the radar bucket, and does not ask again at once', async () => {
    const calls = stubDpc({
      link: (time) => ({ key: dpcKey(time), url: signedLink(time, 'https://evil.example') }),
    });
    const store = new DpcStore({ counters: new MemoryCounters(), userAgent: 'test' });
    await expect(store.grid(NEWEST)).rejects.toThrow();
    await expect(store.grid(NEWEST)).rejects.toThrow();
    expect(calls.some((c) => c.url.includes('evil.example'))).toBe(false);
    expect(downloads(calls)).toHaveLength(1);
  });

  it('does not ask again for a frame that just failed', async () => {
    const calls = stubDpc({ tiff: () => new Response('nope', { status: 403 }) });
    const store = new DpcStore({ counters: new MemoryCounters(), userAgent: 'test' });
    await expect(store.grid(NEWEST)).rejects.toThrow();
    await expect(store.grid(NEWEST)).rejects.toThrow();
    expect(tiffs(calls)).toHaveLength(1);
  });

  it('keeps a grid two and a half hours in the shared cache, apart from OPERA’s', async () => {
    stubDpc();
    let clock = NOW;
    const counters = new MemoryCounters({ now: () => clock });
    const store = new DpcStore({ counters, userAgent: 'test' });
    await store.grid(NEWEST);
    expect(counters.keys().filter((k) => k.startsWith('opera:'))).toEqual([]);
    clock += 149 * 60_000;
    expect(await counters.get(store.gridKey(NEWEST))).toBeDefined();
    clock += 2 * 60_000;
    expect(await counters.get(store.gridKey(NEWEST))).toBeUndefined();
  });
});

describe('GET /weather/radar/dpc/*: the gate', () => {
  const both = [
    () => frames(new Request(FRAMES_URL, { headers: AUTH })),
    () => image(imageQuery(goodQuery)),
  ];
  const bare = [() => frames(new Request(FRAMES_URL)), () => image(new Request(`${IMAGE_URL}?time=x`))];

  it('refuses without a bearer, before anything else', async () => {
    const calls = stubDpc();
    await withEnv({ REVENUECAT_MODE: 'live', REVENUECAT_SECRET_KEY: 'sk' }, async () => {
      for (const call of bare) {
        const res = await call();
        expect(res.status).toBe(401);
        expect((await errOf(res)).code).toBe('not_entitled');
      }
    });
    expect(calls).toHaveLength(0);
  });

  it('refuses a rider whose Plus expired, asking the DPC nothing', async () => {
    const calls = stubDpc({
      revenueCat: () =>
        Response.json({
          subscriber: { entitlements: { plus: { expires_date: '2026-10-01T00:00:00Z' } } },
        }),
    });
    await withEnv({ REVENUECAT_MODE: 'live', REVENUECAT_SECRET_KEY: 'sk' }, async () => {
      for (const call of both) {
        const res = await call();
        expect(res.status).toBe(401);
        expect((await errOf(res)).code).toBe('not_entitled');
      }
    });
    expect(calls.every((c) => c.url.startsWith('https://api.revenuecat.com/'))).toBe(true);
  });

  it('serves a rider with Plus', async () => {
    stubDpc({
      revenueCat: () =>
        Response.json({ subscriber: { entitlements: { plus: { expires_date: null } } } }),
    });
    await withEnv({ REVENUECAT_MODE: 'live', REVENUECAT_SECRET_KEY: 'sk' }, async () => {
      for (const call of both) expect((await call()).status).toBe(200);
    });
  });

  it('rate limits per rider, counted apart from OPERA', async () => {
    stubDpc();
    await withEnv({}, async () => {
      const operaUrl = 'https://api.velorki.com/weather/radar/opera/frames';
      for (let i = 0; i < 60; i += 1) {
        expect((await operaFrames(new Request(operaUrl, { headers: AUTH }))).status).toBe(200);
      }
      // OPERA's minute is used up; the DPC's is not.
      expect((await operaFrames(new Request(operaUrl, { headers: AUTH }))).status).toBe(429);
      for (let i = 0; i < 60; i += 1) {
        expect((await frames(new Request(FRAMES_URL, { headers: AUTH }))).status).toBe(200);
      }
      const res = await image(imageQuery(goodQuery));
      expect(res.status).toBe(429);
      expect((await errOf(res)).code).toBe('rate_limited');
      expect(res.headers.get('retry-after')).not.toBeNull();
    });
  });
});

describe('GET /weather/radar/dpc/frames', () => {
  it('lists the frames and the newest, with the DPC’s credit, not to be cached', async () => {
    stubDpc();
    await withEnv({}, async () => {
      const res = await frames(new Request(FRAMES_URL, { headers: AUTH }));
      expect(res.status).toBe(200);
      expect(res.headers.get('cache-control')).toBe('no-store');
      expect(res.headers.get('access-control-allow-origin')).toBeNull();
      const body = await bodyOf<{ frames: string[]; newest: string; stepMinutes: number; attribution: string }>(res);
      expect(body.newest).toBe('2026-10-12T21:00:00.000Z');
      expect(body.frames.at(-1)).toBe(body.newest);
      expect(body.stepMinutes).toBe(5);
      expect(body.attribution).toBe(
        'Radar: Radar-DPC, Dipartimento della Protezione Civile (CC BY-SA 4.0)',
      );
    });
  });

  it('answers 502 without the API’s words when it fails or says nonsense', async () => {
    for (const last of [
      () => new Response('<html>Access Denied internal detail</html>', { status: 403 }),
      () => Response.json({ total: 0, lastProducts: [] }),
      () => new Response('not json at all', { status: 200 }),
    ]) {
      stubDpc({ last });
      await withEnv({}, async () => {
        const res = await frames(new Request(FRAMES_URL, { headers: AUTH }));
        expect(res.status).toBe(502);
        const err = await errOf(res);
        expect(err.code).toBe('upstream_error');
        expect(err.message).not.toMatch(/internal detail|protezionecivile|amazonaws/i);
      });
      vi.unstubAllGlobals();
    }
  });
});

describe('GET /weather/radar/dpc/image', () => {
  it('draws the frame over the box: Rome in its class, private cache', async () => {
    const calls = stubDpc();
    await withEnv({}, async () => {
      const res = await image(imageQuery(goodQuery));
      expect(res.status).toBe(200);
      expect(res.headers.get('content-type')).toBe('image/png');
      expect(res.headers.get('cache-control')).toBe('private, max-age=3600');
      expect(res.headers.get('access-control-allow-origin')).toBeNull();
      const { width, height, px } = pngIndices(new Uint8Array(await res.arrayBuffer()));
      expect([width, height]).toEqual([5, 5]);
      expect(px[2 * 5 + 2]).toBe(9);
      expect(px.filter((v) => v === 9)).toHaveLength(1);
      expect(px.filter((v) => v === 3).length).toBeGreaterThan(10);
    });
    // Only URLs the server built, and the link the API gave for that frame.
    expect(calls.map((c) => `${c.method} ${c.url}`)).toEqual([
      `GET ${LAST_URL}`,
      `POST ${DOWNLOAD_URL}`,
      `GET ${new URL(signedLink(NEWEST)).toString()}`,
    ]);
  });

  it('refuses a time that is not a listed frame, asking the DPC for no frame', async () => {
    const calls = stubDpc();
    await withEnv({}, async () => {
      for (const time of [
        '2026-10-12T21:05:00.000Z', // not yet published
        '2026-10-12T18:00:00.000Z', // older than the window
        '2026-10-12T21:01:00.000Z', // off the grid
        '../../etc/passwd',
        'https://evil.example/x.tif',
        '',
      ]) {
        const res = await image(imageQuery({ ...goodQuery, time }));
        expect(res.status).toBe(400);
        expect((await errOf(res)).code).toBe('invalid_request');
      }
    });
    expect(calls.filter((c) => c.url !== LAST_URL)).toEqual([]);
  });

  it('refuses a box or a size out of bounds', async () => {
    const calls = stubDpc();
    const paris = boxAround(48.85, 2.35, 50).join(','); // beyond the DPC's grid
    await withEnv({}, async () => {
      const bad: Record<string, string>[] = [
        { bbox: '1,2,3' },
        { bbox: 'a,b,c,d' },
        { bbox: '0,0,1e12,1' },
        { bbox: '10,10,0,20' },
        { bbox: paris },
        { width: '0' },
        { width: '1537' },
        { height: '2.5' },
        { width: '1536', height: '1' },
      ];
      for (const change of bad) {
        const res = await image(imageQuery({ ...goodQuery, ...change }));
        expect(res.status, JSON.stringify(change)).toBe(400);
      }
    });
    expect(downloads(calls)).toEqual([]);
  });

  it('answers 502 when the frame cannot be had, and does not storm the API', async () => {
    const calls = stubDpc({ link: () => ({ error: 'File non trovato' }) });
    await withEnv({}, async () => {
      for (let i = 0; i < 3; i += 1) {
        const res = await image(imageQuery(goodQuery));
        expect(res.status).toBe(502);
        expect((await errOf(res)).message).toBe('The radar archive did not answer.');
      }
    });
    expect(downloads(calls)).toHaveLength(1);
    expect(tiffs(calls)).toEqual([]);
  });
});
