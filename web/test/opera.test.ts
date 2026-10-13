// SPDX-License-Identifier: AGPL-3.0-only
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { inflateSync } from 'node:zlib';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as frames } from '@/app/(api)/weather/radar/opera/frames/route';
import { GET as image } from '@/app/(api)/weather/radar/opera/image/route';
import { MemoryCounters } from '@/server/counters';
import {
  CLASS_DRY,
  CLASS_NO_DATA,
  DWD_CLASS_COLOURS,
  DWD_CLASS_FLOORS,
  classOfDbz,
  marshallPalmerRate,
} from '@/weather/radar/classes';
import { GRID_VERSION, OPERA_GRID_FORMAT, decodeOperaTiff } from '@/weather/opera/grid';
import { HEAVY_CLASS, dropClutter, parseGrid, serialiseGrid } from '@/weather/radar/grid';
import { Laea } from '@/weather/opera/laea';
import {
  PALETTE_NO_DATA,
  classesOfArea,
  encodeClassPng,
  mercatorOf,
  type MercatorBox,
} from '@/weather/radar/render';
import { MAX_SHARED_BYTES } from '@/weather/radar/store';
import {
  OPERA_BUCKET,
  OperaStore,
  operaGridKey,
  operaKey,
  operaStamp,
  parseListing,
} from '@/weather/opera/store';
import { AUTH, bodyOf, errOf, withEnv } from './helpers';
import { FIXTURE, fixtureTiff } from './opera/fixture';

const NOW = Date.parse('2026-10-12T21:07:30Z');
const NEWEST = Date.parse('2026-10-12T21:05:00Z');
const FRAMES_URL = 'https://api.velorki.com/weather/radar/opera/frames';
const IMAGE_URL = 'https://api.velorki.com/weather/radar/opera/image';

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
      expect(data[9]).toBe(3);
    }
    if (type === 'IDAT') idat.push(data);
    at += 12 + len;
  }
  const raw = inflateSync(Buffer.concat(idat));
  const px = new Uint8Array(width * height);
  for (let y = 0; y < height; y += 1) {
    expect(raw[y * (width + 1)]).toBe(0);
    px.set(raw.subarray(y * (width + 1) + 1, (y + 1) * (width + 1)), y * width);
  }
  return { width, height, px };
}

/** The bucket, answering listings of [frames] and the fixture for any frame. */
function stubBucket(
  opts: { frames?: number[]; tiff?: () => Response; revenueCat?: () => Response } = {},
) {
  const listed = opts.frames ?? [];
  const calls: string[] = [];
  const fetchMock = vi.fn(async (input: string | URL | Request) => {
    const url = String(input instanceof Request ? input.url : input);
    calls.push(url);
    if (url.startsWith('https://api.revenuecat.com/')) {
      return opts.revenueCat?.() ?? new Response('{}', { status: 404 });
    }
    if (!url.startsWith(OPERA_BUCKET)) throw new Error(`unexpected fetch ${url}`);
    const u = new URL(url);
    if (u.searchParams.get('list-type') === '2') {
      const prefix = u.searchParams.get('prefix') ?? '';
      const keys = listed
        .flatMap((t) => [operaKey(t), operaKey(t).replace('DBZH.tiff', 'DBZH.h5')])
        .filter((k) => k.startsWith(prefix));
      const xml =
        '<?xml version="1.0" encoding="UTF-8"?><ListBucketResult>' +
        keys.map((k) => `<Contents><Key>${k}</Key><Size>1</Size></Contents>`).join('') +
        '</ListBucketResult>';
      return new Response(xml, { status: 200, headers: { 'content-type': 'application/xml' } });
    }
    return opts.tiff?.() ?? new Response(Buffer.from(fixtureTiff()), { status: 200 });
  });
  vi.stubGlobal('fetch', fetchMock);
  return calls;
}

const everyFrame = (): number[] => {
  const out: number[] = [];
  for (let t = NEWEST; t > NOW - 2 * 3_600_000; t -= 300_000) out.push(t);
  return out.reverse();
};

function imageQuery(params: Record<string, string>): Request {
  const url = new URL(IMAGE_URL);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  return new Request(url, { headers: AUTH });
}

const PARIS_BOX = boxAround(FIXTURE.paris.lat, FIXTURE.paris.lon, 5);
const goodQuery = {
  time: new Date(NEWEST).toISOString(),
  bbox: PARIS_BOX.join(','),
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

describe('OPERA: classes', () => {
  it('match the app’s DWD legend, the one source of truth', () => {
    const dart = readFileSync(
      join(process.cwd(), '../app/lib/features/map/data/rain_legend.dart'),
      'utf8',
    );
    const legend = /final RainLegend dwdRadarLegend = RainLegend\(const <List<int>>\[([\s\S]*?)\], noData: (0x[0-9A-Fa-f]+)\);/.exec(dart);
    expect(legend).not.toBeNull();
    const colours = [...(legend?.[1] ?? '').matchAll(/<int>\[(0x[0-9A-Fa-f]{6})\]/g)].map((m) =>
      Number(m[1]),
    );
    expect(colours).toEqual([...DWD_CLASS_COLOURS]);
    const floors = /const List<double> dwdRadarClassFloors = <double>\[([\s\S]*?)\];/.exec(dart);
    const values = (floors?.[1] ?? '')
      .split(/[,\s]+/)
      .filter((v) => /^[\d.]+$/.test(v))
      .map(Number);
    expect(values).toEqual([...DWD_CLASS_FLOORS]);
  });

  it('turn dBZ into the class of its Marshall-Palmer rate', () => {
    expect(marshallPalmerRate(40)).toBeCloseTo(11.53, 2);
    expect(classOfDbz(40)).toBe(9); // 10-15 mm/h, the ninth class
    expect(classOfDbz(5)).toBe(CLASS_DRY); // 0.08 mm/h
    expect(classOfDbz(7.1)).toBe(1); // just over 0.1 mm/h
    expect(classOfDbz(-31.5)).toBe(CLASS_DRY);
    expect(classOfDbz(80)).toBe(15); // over 150 mm/h
    for (let k = 0; k < DWD_CLASS_FLOORS.length; k += 1) {
      const floor = DWD_CLASS_FLOORS[k] ?? 0;
      const dbz = 10 * Math.log10(200 * Math.pow(floor, 1.6));
      expect(classOfDbz(dbz + 0.01)).toBe(k + 1);
      expect(classOfDbz(dbz - 0.01)).toBe(k);
    }
  });
});

describe('OPERA: clutter', () => {
  /** A grid from rows of text: `.` dry, `#` no data, a digit the class. */
  function grid(rows: string[]): { cells: Uint8Array; width: number; height: number } {
    const width = rows[0]?.length ?? 0;
    const cells = new Uint8Array(width * rows.length);
    rows.forEach((row, r) => {
      [...row].forEach((ch, c) => {
        cells[r * width + c] = ch === '.' ? CLASS_DRY : ch === '#' ? CLASS_NO_DATA : Number(ch);
      });
    });
    return { cells, width, height: rows.length };
  }
  const filtered = (rows: string[]) => {
    const g = grid(rows);
    dropClutter(g.cells, g.width, g.height);
    return [...g.cells].map((v) => (v === CLASS_DRY ? '.' : v === CLASS_NO_DATA ? '#' : String(v)));
  };

  it('drops patches under four cells, counting diagonal neighbours', () => {
    const out = filtered([
      '1.....2.',
      '......2.',
      '..3.....',
      '...3....',
      '....3.##',
      '.....3##',
    ]);
    // The single cell and the pair go; the diagonal four stay.
    expect(out.filter((v) => v === '1' || v === '2')).toEqual([]);
    expect(out.filter((v) => v === '3')).toHaveLength(4);
    expect(out.filter((v) => v === '#')).toHaveLength(4);
  });

  it('drops a patch mostly heavy, a spoke, and keeps a shower with its rim', () => {
    expect(HEAVY_CLASS).toBe(7);
    const spoke = filtered(['........', '.999999.', '.....1..']);
    expect(spoke.filter((v) => v !== '.')).toEqual([]);
    const shower = filtered(['.2222.', '.2992.', '.2992.', '.2222.']);
    expect(shower.filter((v) => v === '9')).toHaveLength(4);
    // Exactly half heavy stays.
    const half = filtered(['7711']);
    expect(half).toEqual(['7', '7', '1', '1']);
  });

  it('shares grids under a key of the current version, an old one unread', async () => {
    expect(GRID_VERSION).toBeGreaterThan(1);
    const calls = stubBucket({ frames: everyFrame() });
    const counters = new MemoryCounters();
    // A grid of version 1, unfiltered, of the frame asked for.
    await counters.set(`opera:grid:v1:${operaStamp(NEWEST)}`, new Uint8Array([1, 2, 3]));
    const store = new OperaStore({ counters, userAgent: 'test' });
    await store.grid(NEWEST);
    expect(calls.filter((u) => u.endsWith('.tiff'))).toHaveLength(1);
    expect(operaGridKey(NEWEST)).toBe(`opera:grid:v${String(GRID_VERSION)}:${operaStamp(NEWEST)}`);
    expect(counters.keys()).toContain(operaGridKey(NEWEST));
  });
});

describe('OPERA: projection and decoding', () => {
  it('projects the EPSG guidance note’s example exactly', () => {
    // EPSG Guidance Note 7-2, method 9820 (ETRS89-extended / LAEA Europe).
    const laea = new Laea({
      lat0: 52,
      lon0: 10,
      falseEasting: 4_321_000,
      falseNorthing: 3_210_000,
      a: 6_378_137,
      invFlattening: 298.257222101,
    });
    const p = laea.forward(50, 5);
    expect(p?.x).toBeCloseTo(3_962_799.45, 1);
    expect(p?.y).toBeCloseTo(2_999_718.85, 1);
  });

  it('reads the projection from the GeoKeys and classes every cell', async () => {
    const grid = await decodeOperaTiff(fixtureTiff());
    expect(grid.proj).toEqual({
      lat0: 55,
      lon0: 10,
      falseEasting: 1_950_000,
      falseNorthing: -2_100_000,
      a: 6_378_137,
      invFlattening: 298.257223563,
    });
    expect([grid.width, grid.height, grid.x0, grid.y0, grid.dx, grid.dy]).toEqual([
      20, 20, FIXTURE.x0, FIXTURE.y0, 1000, 1000,
    ]);
    const at = (col: number, row: number) => grid.cells[row * grid.width + col];
    expect(at(FIXTURE.paris.col, FIXTURE.paris.row)).toBe(9);
    expect(at(FIXTURE.weak.col, FIXTURE.weak.row)).toBe(CLASS_DRY);
    expect(at(0, 0)).toBe(CLASS_DRY);
    expect(at(5, FIXTURE.noDataFromRow)).toBe(CLASS_NO_DATA);
    expect(at(FIXTURE.paris.col + 2, FIXTURE.paris.row - 2)).toBe(3);
    // The spoke and the speck are gone; unfiltered they are there.
    expect(at(FIXTURE.spoke.fromCol + 2, FIXTURE.spoke.row)).toBe(CLASS_DRY);
    expect(at(FIXTURE.speck.col, FIXTURE.speck.row)).toBe(CLASS_DRY);
    const raw = await decodeOperaTiff(fixtureTiff(), { filter: false });
    expect(raw.cells[FIXTURE.spoke.row * 20 + FIXTURE.spoke.fromCol + 2]).toBe(classOfDbz(50));
    expect(raw.cells[FIXTURE.speck.row * 20 + FIXTURE.speck.col]).toBe(3);

    const back = await parseGrid(await serialiseGrid(grid, OPERA_GRID_FORMAT), OPERA_GRID_FORMAT);
    expect(back).toEqual(grid);
  });

  it('refuses a GeoTIFF in another projection', async () => {
    const bytes = fixtureTiff();
    // GeoKey 3075 (ProjCoordTransGeoKey) = 10 -> 11 (Azimuthal Equidistant).
    const buf = Buffer.from(bytes);
    const big = buf.toString('ascii', 0, 2) === 'MM';
    const entry = big ? [0x0c, 0x03, 0, 0, 0, 1, 0, 10] : [0x03, 0x0c, 0, 0, 1, 0, 10, 0];
    const at = buf.indexOf(Buffer.from(entry));
    expect(at).toBeGreaterThan(0);
    buf[at + (big ? 7 : 6)] = 11;
    await expect(decodeOperaTiff(new Uint8Array(buf))).rejects.toThrow(/Lambert/);
  });

  it('puts a known place on its cell: Paris on the rain, south of it no data', async () => {
    const grid = await decodeOperaTiff(fixtureTiff());
    const one = (lat: number, lon: number) =>
      classesOfArea(grid, new Laea(grid.proj), boxAround(lat, lon, 0.2), 1, 1)[0];
    expect(one(FIXTURE.paris.lat, FIXTURE.paris.lon)).toBe(9);
    // A kilometre and a half east is the next cell: the shower's light rim.
    expect(one(FIXTURE.paris.lat, FIXTURE.paris.lon + 0.02)).toBe(3);
    // Five kilometres east, past the rim: dry, transparent.
    expect(one(FIXTURE.paris.lat, FIXTURE.paris.lon + 0.07)).toBe(0);
    // Ten kilometres south lies in the rows of no data.
    expect(one(FIXTURE.paris.lat - 0.09, FIXTURE.paris.lon)).toBe(PALETTE_NO_DATA);
    // Far off the grid: transparent.
    expect(one(40, -3)).toBe(0);
  });

  it('keeps a cell of rain when a pixel spans several cells', async () => {
    const grid = await decodeOperaTiff(fixtureTiff());
    // 3 x 3 pixels over some 30 km: each pixel some 10 km, more than one cell.
    const box = boxAround(FIXTURE.paris.lat, FIXTURE.paris.lon, 30);
    const px = classesOfArea(grid, new Laea(grid.proj), box, 3, 3);
    expect(px[4]).toBe(9);
  });

  it('encodes an indexed PNG in the DWD colours, no data grey and see-through', async () => {
    const png = await encodeClassPng(3, 1, new Uint8Array([0, 9, PALETTE_NO_DATA]));
    const buf = Buffer.from(png);
    const plteAt = buf.indexOf('PLTE');
    const plte = buf.subarray(plteAt + 4, plteAt + 4 + buf.readUInt32BE(plteAt - 4));
    const rgb = (i: number) => ((plte[i * 3] ?? 0) << 16) | ((plte[i * 3 + 1] ?? 0) << 8) | (plte[i * 3 + 2] ?? 0);
    expect(rgb(9)).toBe(0xff8901);
    expect(rgb(PALETTE_NO_DATA)).toBe(0x7e7e7e);
    const trnsAt = buf.indexOf('tRNS');
    expect(buf[trnsAt + 4]).toBe(0);
    expect(buf[trnsAt + 4 + 9]).toBe(255);
    expect(buf[trnsAt + 4 + PALETTE_NO_DATA]).toBe(77);
    expect(pngIndices(png).px).toEqual(new Uint8Array([0, 9, PALETTE_NO_DATA]));
  });
});

describe('OPERA: the store', () => {
  it('reads the frames off the bucket listing, one listing per hour', async () => {
    const calls = stubBucket({ frames: everyFrame() });
    const store = new OperaStore({ counters: new MemoryCounters(), userAgent: 'test' });
    const got = await store.frames();
    expect(got).toEqual(everyFrame().filter((t) => t >= NOW - 2 * 3_600_000));
    expect(got.at(-1)).toBe(NEWEST);
    // 19:07 to 21:07: three hours listed, once.
    expect(calls).toHaveLength(3);
    await store.frames();
    expect(calls).toHaveLength(3);
    expect(parseListing('<Key>2026/10/12/OPERA/COMP/OPERA@20261012T2105@0@RATE.tiff</Key>')).toEqual([]);
  });

  it('fetches a frame once, for concurrent requests and for another worker', async () => {
    const calls = stubBucket({ frames: everyFrame() });
    const counters = new MemoryCounters();
    const store = new OperaStore({ counters, userAgent: 'test' });
    await Promise.all([
      store.image(NEWEST, PARIS_BOX, 5, 5),
      store.image(NEWEST, PARIS_BOX, 5, 5),
      store.grid(NEWEST),
    ]);
    const tiffs = () => calls.filter((u) => u.endsWith('.tiff'));
    expect(tiffs()).toEqual([`${OPERA_BUCKET}/${operaKey(NEWEST)}`]);
    const shared = await counters.get<Uint8Array>(operaGridKey(NEWEST));
    expect(shared).toBeInstanceOf(Uint8Array);
    expect(shared?.length).toBeLessThan(MAX_SHARED_BYTES);
    // Another worker: the same shared cache, its own memory.
    const other = new OperaStore({ counters, userAgent: 'test' });
    expect(await other.grid(NEWEST)).toEqual(await store.grid(NEWEST));
    await other.image(NEWEST, PARIS_BOX, 5, 5);
    expect(tiffs()).toHaveLength(1);
  });

  it('waits for the worker that fetches, instead of fetching too', async () => {
    let release: () => void = () => undefined;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    const calls = stubBucket({ frames: everyFrame() });
    const counters = new MemoryCounters();
    const slow = vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
      await gate;
      return fetch(input, init);
    });
    const first = new OperaStore({ counters, userAgent: 'test', fetch: slow });
    const second = new OperaStore({ counters, userAgent: 'test' });
    const a = first.grid(NEWEST);
    await vi.waitFor(() => expect(slow).toHaveBeenCalled());
    const b = second.grid(NEWEST);
    release();
    expect(await b).toEqual(await a);
    expect(calls.filter((u) => u.endsWith('.tiff'))).toHaveLength(1);
  });

  it('keeps a grid two and a half hours in the shared cache', async () => {
    stubBucket({ frames: everyFrame() });
    let clock = NOW;
    const counters = new MemoryCounters({ now: () => clock });
    await new OperaStore({ counters, userAgent: 'test' }).grid(NEWEST);
    clock += 149 * 60_000;
    expect(await counters.get(operaGridKey(NEWEST))).toBeDefined();
    clock += 2 * 60_000;
    expect(await counters.get(operaGridKey(NEWEST))).toBeUndefined();
  });

  it('serves a grid too large to share from memory, sharing nothing', async () => {
    const calls = stubBucket({ frames: everyFrame() });
    const counters = new MemoryCounters();
    const warn = vi.fn();
    const store = new OperaStore({
      counters,
      userAgent: 'test',
      maxSharedBytes: 10,
      log: { info: () => undefined, warn },
    });
    const png = await store.image(NEWEST, PARIS_BOX, 5, 5);
    expect(png.length).toBeGreaterThan(0);
    expect(await counters.get(operaGridKey(NEWEST))).toBeUndefined();
    expect(warn).toHaveBeenCalledWith(
      expect.objectContaining({ frame: operaStamp(NEWEST) }),
      'opera grid too large to share',
    );
    // Another worker fetches its own.
    await new OperaStore({ counters, userAgent: 'test', maxSharedBytes: 10 }).grid(NEWEST);
    expect(calls.filter((u) => u.endsWith('.tiff'))).toHaveLength(2);
  });

  it('serves a grid the shared cache refuses', async () => {
    stubBucket({ frames: everyFrame() });
    const counters = new MemoryCounters();
    vi.spyOn(counters, 'set').mockImplementation(async (key) => {
      if (key.startsWith('opera:grid:')) throw new Error('exceeds max 1048576 bytes');
    });
    const store = new OperaStore({ counters, userAgent: 'test' });
    expect((await store.grid(NEWEST)).width).toBe(20);
  });

  it('does not ask again for a frame that just failed', async () => {
    const calls = stubBucket({ frames: everyFrame(), tiff: () => new Response('nope', { status: 500 }) });
    const store = new OperaStore({ counters: new MemoryCounters(), userAgent: 'test' });
    await expect(store.grid(NEWEST)).rejects.toThrow();
    await expect(store.grid(NEWEST)).rejects.toThrow();
    expect(calls.filter((u) => u.endsWith('.tiff'))).toHaveLength(1);
  });
});

describe('GET /weather/radar/opera/*: the gate', () => {
  const both = [
    () => frames(new Request(FRAMES_URL, { headers: AUTH })),
    () => image(imageQuery(goodQuery)),
  ];
  const bare = [() => frames(new Request(FRAMES_URL)), () => image(new Request(`${IMAGE_URL}?time=x`))];

  it('refuses without a bearer, before anything else', async () => {
    const calls = stubBucket({ frames: everyFrame() });
    await withEnv({ REVENUECAT_MODE: 'live', REVENUECAT_SECRET_KEY: 'sk' }, async () => {
      for (const call of bare) {
        const res = await call();
        expect(res.status).toBe(401);
        expect((await errOf(res)).code).toBe('not_entitled');
      }
    });
    expect(calls).toHaveLength(0);
  });

  it('refuses a rider whose Plus expired, and one RevenueCat does not know', async () => {
    for (const revenueCat of [
      () =>
        new Response(
          JSON.stringify({
            subscriber: { entitlements: { plus: { expires_date: '2026-10-01T00:00:00Z' } } },
          }),
          { status: 200, headers: { 'content-type': 'application/json' } },
        ),
      () => new Response('{}', { status: 404 }),
    ]) {
      const calls = stubBucket({ frames: everyFrame(), revenueCat });
      await withEnv({ REVENUECAT_MODE: 'live', REVENUECAT_SECRET_KEY: 'sk' }, async () => {
        for (const call of both) {
          const res = await call();
          expect(res.status).toBe(401);
          expect((await errOf(res)).code).toBe('not_entitled');
        }
      });
      expect(calls.every((u) => u.startsWith('https://api.revenuecat.com/'))).toBe(true);
    }
  });

  it('serves a rider with Plus', async () => {
    stubBucket({
      frames: everyFrame(),
      revenueCat: () =>
        new Response(JSON.stringify({ subscriber: { entitlements: { plus: { expires_date: null } } } }), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        }),
    });
    await withEnv({ REVENUECAT_MODE: 'live', REVENUECAT_SECRET_KEY: 'sk' }, async () => {
      for (const call of both) expect((await call()).status).toBe(200);
    });
  });

  it('rate limits per rider', async () => {
    stubBucket({ frames: everyFrame() });
    await withEnv({}, async () => {
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

describe('GET /weather/radar/opera/frames', () => {
  it('lists the frames and the newest, not to be cached', async () => {
    stubBucket({ frames: everyFrame() });
    await withEnv({}, async () => {
      const res = await frames(new Request(FRAMES_URL, { headers: AUTH }));
      expect(res.status).toBe(200);
      expect(res.headers.get('cache-control')).toBe('no-store');
      expect(res.headers.get('access-control-allow-origin')).toBeNull();
      const body = await bodyOf<{ frames: string[]; newest: string; stepMinutes: number; attribution: string }>(res);
      expect(body.newest).toBe('2026-10-12T21:05:00.000Z');
      expect(body.frames.at(-1)).toBe(body.newest);
      expect(body.stepMinutes).toBe(5);
      expect(body.attribution).toBe('Radar: EUMETNET OPERA (CC BY 4.0)');
    });
  });

  it('answers 502 without the archive’s words when the bucket fails', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('<Error>internal detail</Error>', { status: 503 })));
    await withEnv({}, async () => {
      const res = await frames(new Request(FRAMES_URL, { headers: AUTH }));
      expect(res.status).toBe(502);
      const err = await errOf(res);
      expect(err.code).toBe('upstream_error');
      expect(err.message).not.toMatch(/internal detail|cloudferro|s3/i);
    });
  });
});

describe('GET /weather/radar/opera/image', () => {
  it('draws the frame over the box: Paris in its class, private cache', async () => {
    const calls = stubBucket({ frames: everyFrame() });
    await withEnv({}, async () => {
      const res = await image(imageQuery(goodQuery));
      expect(res.status).toBe(200);
      expect(res.headers.get('content-type')).toBe('image/png');
      expect(res.headers.get('cache-control')).toBe('private, max-age=3600');
      expect(res.headers.get('access-control-allow-origin')).toBeNull();
      const { width, height, px } = pngIndices(new Uint8Array(await res.arrayBuffer()));
      expect([width, height]).toEqual([5, 5]);
      // The middle of the box is Paris, the shower's core in its light rim.
      expect(px[2 * 5 + 2]).toBe(9);
      expect(px.filter((v) => v === 9)).toHaveLength(1);
      expect(px.filter((v) => v === 3).length).toBeGreaterThan(10);
    });
    // Only URLs the server built: the listings and the one frame's key.
    for (const url of calls) {
      expect(url.startsWith(`${OPERA_BUCKET}?list-type=2&prefix=2026%2F10%2F12%2FOPERA%2FCOMP%2FOPERA%40`) ||
        url === `${OPERA_BUCKET}/${operaKey(NEWEST)}`).toBe(true);
    }
  });

  it('refuses a time that is not a listed frame, asking the bucket for no frame', async () => {
    const calls = stubBucket({ frames: everyFrame() });
    await withEnv({}, async () => {
      for (const time of [
        '2026-10-12T21:10:00.000Z', // not yet listed
        '2026-10-12T18:00:00.000Z', // older than the window
        '2026-10-12T21:06:00.000Z', // off the grid
        '../../etc/passwd',
        'https://evil.example/x.tiff',
        '',
      ]) {
        const res = await image(imageQuery({ ...goodQuery, time }));
        expect(res.status).toBe(400);
        expect((await errOf(res)).code).toBe('invalid_request');
      }
    });
    expect(calls.filter((u) => !u.includes('list-type=2'))).toEqual([]);
  });

  it('refuses a box or a size out of bounds', async () => {
    const calls = stubBucket({ frames: everyFrame() });
    const far = boxAround(-30, 140, 100).join(','); // Australia: beyond the composite
    await withEnv({}, async () => {
      const bad: Record<string, string>[] = [
        { bbox: '1,2,3' },
        { bbox: 'a,b,c,d' },
        { bbox: '1,2,3,NaN' },
        { bbox: '0,0,1e12,1' },
        { bbox: '10,10,0,20' }, // west after east
        { bbox: far },
        { width: '0' },
        { width: '1537' },
        { height: '2.5' },
        { height: '-4' },
        { width: '1536', height: '1' }, // a pixel 1536 times wider than tall
      ];
      for (const change of bad) {
        const res = await image(imageQuery({ ...goodQuery, ...change }));
        expect(res.status, JSON.stringify(change)).toBe(400);
      }
      const missing = await image(new Request(`${IMAGE_URL}?time=${goodQuery.time}`, { headers: AUTH }));
      expect(missing.status).toBe(400);
    });
    expect(calls.filter((u) => u.endsWith('.tiff'))).toEqual([]);
  });

  it('answers 502 when the frame cannot be had, and does not storm the bucket', async () => {
    const calls = stubBucket({ frames: everyFrame(), tiff: () => new Response('x', { status: 500 }) });
    await withEnv({}, async () => {
      for (let i = 0; i < 3; i += 1) {
        const res = await image(imageQuery(goodQuery));
        expect(res.status).toBe(502);
        expect((await errOf(res)).message).toBe('The radar archive did not answer.');
      }
    });
    expect(calls.filter((u) => u.endsWith('.tiff'))).toHaveLength(1);
  });
});
