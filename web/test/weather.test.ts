// SPDX-License-Identifier: AGPL-3.0-only
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pino } from 'pino';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as weather } from '@/app/(api)/weather/route';
import { injectSingletons } from '@/server/singletons';
import { metnoInFlight } from '@/weather/metno';
import { AUTH, bodyOf, errOf, jsonRequest, withEnv } from './helpers';

const WEATHER_URL = 'https://api.velorki.com/weather';
const NOW = Date.parse('2026-10-10T20:30:00Z');
const FROM = '2026-10-10T20:00:00Z';

const NYC = { lat: 40.75, lon: -74 };
const BERLIN = { lat: 52.525, lon: 13.4 };
const OSLO = { lat: 59.925, lon: 10.75, alt: 50 };
const TOKYO = { lat: 35.675, lon: 139.7 };

interface Hour {
  t: string;
  temp: number;
  wind: number;
  windDir: number;
  gust: number | null;
  precip: number;
  precipProb: number | null;
  cloud: number | null;
}
interface WeatherBody {
  cells: { source: string | null; hours: Hour[] }[];
  sources: { id: string; name: string; url: string; licence: string }[];
}

function fixture(name: string): string {
  return readFileSync(join(process.cwd(), 'test/fixtures/weather', name), 'utf8');
}

const jsonReply = (body: string, status = 200, headers: Record<string, string> = {}) =>
  new Response(body, { status, headers: { 'content-type': 'application/json', ...headers } });

type Reply = (url: URL, headers: Headers) => Response | Promise<Response>;
interface Upstream {
  points: Reply;
  grid: Reply;
  brightsky: Reply;
  metno: Reply;
}

const LAST_MODIFIED = 'Sat, 10 Oct 2026 19:41:22 GMT';

/** The four upstreams, answering from the fixtures. */
const defaults: Upstream = {
  points: () => jsonReply(fixture('nws-points.json')),
  grid: () => jsonReply(fixture('nws-grid.json')),
  brightsky: (url) =>
    jsonReply(
      fixture(url.searchParams.has('source_id') ? 'brightsky-station.json' : 'brightsky-berlin.json'),
    ),
  metno: () =>
    jsonReply(fixture('metno-complete.json'), 200, {
      expires: new Date(Date.now() + 30 * 60_000).toUTCString(),
      'last-modified': LAST_MODIFIED,
    }),
};

interface Call {
  url: URL;
  headers: Headers;
}

/** Stub fetch by URL; every upstream call is recorded. */
function stubUpstream(overrides: Partial<Upstream> = {}): Call[] {
  const replies = { ...defaults, ...overrides };
  const calls: Call[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: string | URL, init: RequestInit = {}) => {
      const url = new URL(String(input));
      const headers = new Headers(init.headers);
      calls.push({ url, headers });
      if (url.href.startsWith('https://api.weather.gov/points/')) return replies.points(url, headers);
      if (url.href.startsWith('https://api.weather.gov/gridpoints/')) return replies.grid(url, headers);
      if (url.href.startsWith('https://api.brightsky.dev/weather')) return replies.brightsky(url, headers);
      if (url.href.startsWith('https://api.met.no/')) return replies.metno(url, headers);
      throw new Error(`unexpected fetch ${url.href}`);
    }),
  );
  return calls;
}

const callsTo = (calls: Call[], host: string) => calls.filter((c) => c.url.host === host);

function ask(body: unknown, headers: Record<string, string> = AUTH): Promise<Response> {
  return weather(jsonRequest(WEATHER_URL, body, headers));
}

function query(cells: unknown[], extra: Record<string, unknown> = {}) {
  return { from: FROM, hours: 6, cells, ...extra };
}

async function answer(cells: unknown[], extra: Record<string, unknown> = {}): Promise<WeatherBody> {
  const res = await ask(query(cells, extra));
  expect(res.status).toBe(200);
  return bodyOf<WeatherBody>(res);
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe('POST /weather: the gate', () => {
  it('requires entitlement', async () => {
    const calls = stubUpstream();
    await withEnv({ REVENUECAT_MODE: 'live', REVENUECAT_SECRET_KEY: 'sk' }, async () => {
      const res = await ask(query([BERLIN]), {});
      expect(res.status).toBe(401);
      expect((await errOf(res)).code).toBe('not_entitled');
    });
    expect(calls).toHaveLength(0);
  });

  it('rejects bad bodies before asking anyone', async () => {
    const calls = stubUpstream();
    await withEnv({}, async () => {
      const cases: [string, unknown][] = [
        ['too many cells', query(Array.from({ length: 151 }, () => BERLIN))],
        ['no cells', query([])],
        ['lat finer than 3 decimals', query([{ lat: 52.5251, lon: 13.4 }])],
        ['lon finer than 3 decimals', query([{ lat: 52.525, lon: 13.4001 }])],
        ['lat out of range', query([{ lat: 91, lon: 13.4 }])],
        ['alt out of range', query([{ ...BERLIN, alt: 9001 }])],
        ['alt not whole', query([{ ...BERLIN, alt: 12.5 }])],
        ['zero hours', query([BERLIN], { hours: 0 })],
        ['too many hours', query([BERLIN], { hours: 73 })],
        ['fractional hours', query([BERLIN], { hours: 1.5 })],
        ['from too early', query([BERLIN], { from: '2026-10-10T17:00:00Z' })],
        ['from too late', query([BERLIN], { from: '2026-10-19T21:00:00Z' })],
        ['from not UTC', query([BERLIN], { from: '2026-10-10T22:00:00+02:00' })],
        ['no from', { hours: 6, cells: [BERLIN] }],
      ];
      for (const [name, body] of cases) {
        const res = await ask(body);
        expect(res.status, name).toBe(400);
        expect((await errOf(res)).code, name).toBe('invalid_request');
      }
      const precision = await errOf(await ask(query([{ lat: 52.5251, lon: 13.4 }])));
      expect(precision.message).toBe('cells.0.lat: must have at most 3 decimals');
    });
    expect(calls).toHaveLength(0);
  });

  it('accepts every 0.025° grid value despite float noise', async () => {
    stubUpstream();
    await withEnv({}, async () => {
      const cells = [0.025, 0.075, 0.175, 12.325, 47.975, -33.875].map((v) => ({ lat: v, lon: v }));
      const body = await answer(cells);
      expect(body.cells).toHaveLength(cells.length);
    });
  });

  it('rate limits at 60 per hour per rider', async () => {
    stubUpstream();
    await withEnv({}, async () => {
      for (let i = 0; i < 60; i += 1) {
        expect((await ask(query([BERLIN], { hours: 0 }))).status, `call ${String(i)}`).toBe(400);
      }
      const limited = await ask(query([BERLIN]));
      expect(limited.status).toBe(429);
      expect((await errOf(limited)).code).toBe('rate_limited');
    });
  });

  it('answers 503 when weather is switched off', async () => {
    stubUpstream();
    await withEnv({ WEATHER_PROVIDERS: 'none' }, async () => {
      const res = await ask(query([BERLIN]));
      expect(res.status).toBe(503);
      expect((await errOf(res)).code).toBe('unavailable');
    });
  });
});

describe('POST /weather: routing', () => {
  it('sends each cell to the provider that covers it', async () => {
    const calls = stubUpstream();
    await withEnv({}, async () => {
      const body = await answer([NYC, BERLIN, OSLO, TOKYO]);
      expect(body.cells.map((c) => c.source)).toEqual(['nws', 'dwd', 'metno', 'metno']);
      expect(body.sources.map((s) => s.id)).toEqual(['nws', 'dwd', 'metno']);

      expect(callsTo(calls, 'api.weather.gov').map((c) => c.url.pathname)).toEqual([
        '/points/40.75,-74',
        '/gridpoints/OKX/33,44',
      ]);
      const [brightsky] = callsTo(calls, 'api.brightsky.dev');
      expect(brightsky?.url.searchParams.get('lat')).toBe('52.525');
      expect(brightsky?.url.searchParams.get('lon')).toBe('13.4');
      expect(brightsky?.url.searchParams.get('max_dist')).toBe('25000');
      expect(brightsky?.url.searchParams.get('tz')).toBe('Etc/UTC');
      // Oslo keeps its 0.025° cell inside MET's Nordic model; Tokyo is
      // asked at 0.1°, without an altitude it was not given.
      expect(callsTo(calls, 'api.met.no').map((c) => c.url.search).sort()).toEqual([
        '?lat=35.7&lon=139.7',
        '?lat=59.925&lon=10.75&altitude=50',
      ]);
    });
  });

  it('answers in request order, one entry per cell, asking once per point', async () => {
    const calls = stubUpstream();
    await withEnv({}, async () => {
      const body = await answer([TOKYO, BERLIN, TOKYO, NYC, { lat: 35.7, lon: 139.725 }]);
      expect(body.cells.map((c) => c.source)).toEqual(['metno', 'dwd', 'metno', 'nws', 'metno']);
      expect(body.cells[0]).toEqual(body.cells[2]);
      // Three Tokyo cells, one MET point.
      expect(callsTo(calls, 'api.met.no')).toHaveLength(1);
      expect(body.sources.map((s) => s.id)).toEqual(['nws', 'dwd', 'metno']);
    });
  });

  it('identifies itself to every upstream', async () => {
    let calls = stubUpstream();
    await withEnv({}, async (ctx) => {
      await answer([NYC, BERLIN, TOKYO]);
      const expected = `Velorki/${ctx.config.APP_VERSION} (+https://share.velorki.test)`;
      expect(calls.map((c) => c.headers.get('user-agent'))).toEqual(calls.map(() => expected));
    });
    calls = stubUpstream();
    await withEnv({ WEATHER_CONTACT: 'ops@example.org' }, async (ctx) => {
      await answer([TOKYO]);
      expect(calls[0]?.headers.get('user-agent')).toBe(
        `Velorki/${ctx.config.APP_VERSION} (+https://share.velorki.test; ops@example.org)`,
      );
    });
  });
});

describe('POST /weather: units and hours', () => {
  it('converts the NWS grid to SI hours', async () => {
    stubUpstream();
    await withEnv({}, async () => {
      const [cell] = (await answer([NYC])).cells;
      expect(cell?.hours.map((h) => h.t)).toEqual([
        '2026-10-10T20:00:00Z',
        '2026-10-10T21:00:00Z',
        '2026-10-10T22:00:00Z',
        '2026-10-10T23:00:00Z',
        '2026-10-11T00:00:00Z',
        '2026-10-11T01:00:00Z',
      ]);
      expect(cell?.hours[0]).toEqual({
        t: '2026-10-10T20:00:00Z',
        temp: 13.3,
        wind: 2.6, // 9.26 km/h
        windDir: 30,
        gust: 6.2, // 22.224 km/h
        precip: 0.2, // 1.2 mm over PT6H
        precipProb: 20,
        cloud: 44,
      });
      // 21:00/PT2H holds for 22:00; the second wind interval starts at 00:00.
      expect(cell?.hours[2]).toMatchObject({ temp: 12.2, windDir: 40, precip: 0.2 });
      expect(cell?.hours[4]).toMatchObject({ temp: 10, wind: 4.1, precip: 0 });
    });
  });

  it('takes the Bright Sky hour after for what it reports backwards', async () => {
    stubUpstream();
    await withEnv({}, async () => {
      const [cell] = (await answer([BERLIN])).cells;
      expect(cell?.hours).toHaveLength(6);
      expect(cell?.hours[0]).toEqual({
        t: '2026-10-10T20:00:00Z',
        temp: 10.1,
        wind: 3.6, // 13 km/h
        windDir: 226,
        gust: 6.7, // 24.1 km/h, from the 21:00 row
        precip: 0.3, // from the 21:00 row
        precipProb: 3,
        cloud: 24,
      });
    });
  });

  it('interpolates MET six-hourly steps to the hour and stops at the last', async () => {
    stubUpstream();
    await withEnv({}, async () => {
      const [cell] = (await answer([OSLO], { hours: 72 })).cells;
      const hours = cell?.hours ?? [];
      // 20:00 to 11:00: the 12:00 step is the last and has no precipitation.
      expect(hours).toHaveLength(16);
      expect(hours.at(-1)?.t).toBe('2026-10-11T11:00:00Z');
      expect(hours[0]).toEqual({
        t: '2026-10-10T20:00:00Z',
        temp: 8,
        wind: 3,
        windDir: 350,
        gust: 6,
        precip: 0.4,
        precipProb: 30,
        cloud: 50,
      });
      // Halfway from 00:00 to 06:00; the direction crosses north.
      expect(hours.find((h) => h.t === '2026-10-11T03:00:00Z')).toEqual({
        t: '2026-10-11T03:00:00Z',
        temp: 5,
        wind: 3,
        windDir: 0,
        gust: 6,
        precip: 0.1,
        precipProb: 35,
        cloud: 50,
      });
      // A sixth of the way from 06:00 to 12:00, 1.8 mm split over six hours.
      expect(hours.find((h) => h.t === '2026-10-11T07:00:00Z')).toEqual({
        t: '2026-10-11T07:00:00Z',
        temp: 5,
        wind: 4.3,
        windDir: 13,
        gust: 8.5,
        precip: 0.3,
        precipProb: 50,
        cloud: 17,
      });
    });
  });

  it('starts at the full hour at or before from', async () => {
    stubUpstream();
    await withEnv({}, async () => {
      const [cell] = (await answer([OSLO], { from: '2026-10-10T21:45:00Z', hours: 2 })).cells;
      expect(cell?.hours.map((h) => h.t)).toEqual(['2026-10-10T21:00:00Z', '2026-10-10T22:00:00Z']);
    });
  });
});

describe('POST /weather: fallback', () => {
  it('asks MET when the NWS has no grid for the place, and remembers that', async () => {
    const calls = stubUpstream({ points: () => jsonReply('{"status":404}', 404) });
    await withEnv({}, async () => {
      const body = await answer([NYC]);
      expect(body.cells[0]?.source).toBe('metno');
      expect(body.sources.map((s) => s.id)).toEqual(['metno']);
      await answer([NYC]);
      expect(callsTo(calls, 'api.weather.gov')).toHaveLength(1);
    });
  });

  it('asks MET when the NWS grid fails', async () => {
    stubUpstream({ grid: () => jsonReply('{}', 500) });
    await withEnv({}, async () => {
      expect((await answer([NYC])).cells[0]?.source).toBe('metno');
    });
  });

  it('asks MET when no DWD forecast station is near', async () => {
    stubUpstream({ brightsky: () => jsonReply(fixture('brightsky-no-forecast.json')) });
    await withEnv({}, async () => {
      expect((await answer([BERLIN])).cells[0]?.source).toBe('metno');
    });
  });

  it('asks MET when Bright Sky finds no source at all', async () => {
    stubUpstream({ brightsky: () => jsonReply('{"detail":"No sources match your criteria"}', 404) });
    await withEnv({}, async () => {
      expect((await answer([BERLIN])).cells[0]?.source).toBe('metno');
    });
  });

  it('asks MET when a provider times out', async () => {
    stubUpstream({
      grid: (_url, headers) => {
        void headers;
        throw new DOMException('The operation was aborted.', 'TimeoutError');
      },
    });
    await withEnv({}, async () => {
      expect((await answer([NYC])).cells[0]?.source).toBe('metno');
    });
  });

  it('leaves a cell nobody answered empty and still answers the rest', async () => {
    stubUpstream({
      brightsky: () => jsonReply('{}', 500),
      metno: (url) =>
        url.searchParams.get('lat') === '52.5' ? jsonReply('{}', 500) : defaults.metno(url, new Headers()),
    });
    await withEnv({}, async () => {
      const body = await answer([BERLIN, TOKYO]);
      expect(body.cells[0]).toEqual({ source: null, hours: [] });
      expect(body.cells[1]?.source).toBe('metno');
      expect(body.sources.map((s) => s.id)).toEqual(['metno']);
    });
  });

  it('answers 502 when every cell failed', async () => {
    stubUpstream({
      points: () => jsonReply('{}', 503),
      brightsky: () => jsonReply('{}', 500),
      metno: () => jsonReply('{}', 500),
    });
    await withEnv({}, async () => {
      const res = await ask(query([NYC, BERLIN, TOKYO]));
      expect(res.status).toBe(502);
      expect((await errOf(res)).code).toBe('upstream_error');
    });
  });
});

describe('POST /weather: cache', () => {
  it('answers a repeated request without calling anyone', async () => {
    const calls = stubUpstream();
    await withEnv({}, async () => {
      const first = await answer([NYC, BERLIN, OSLO, TOKYO]);
      const made = calls.length;
      expect(await answer([NYC, BERLIN, OSLO, TOKYO])).toEqual(first);
      expect(calls).toHaveLength(made);
    });
  });

  it('asks the DWD station by id once the cell is known', async () => {
    const calls = stubUpstream();
    await withEnv({}, async () => {
      await answer([BERLIN]);
      // An hour on the forecast is stale, the station is not.
      vi.setSystemTime(NOW + 61 * 60_000);
      const body = await answer([BERLIN], { from: '2026-10-10T21:00:00Z' });
      expect(body.cells[0]?.source).toBe('dwd');
      const asked = callsTo(calls, 'api.brightsky.dev');
      expect(asked).toHaveLength(2);
      expect(asked[1]?.url.searchParams.get('source_id')).toBe('2382');
      expect(asked[1]?.url.searchParams.has('lat')).toBe(false);
    });
  });

  it('revalidates a stale MET forecast with If-Modified-Since and reuses it on 304', async () => {
    const calls = stubUpstream({
      metno: (url, headers) =>
        headers.get('if-modified-since') === LAST_MODIFIED
          ? new Response(null, {
              status: 304,
              headers: { expires: new Date(Date.now() + 30 * 60_000).toUTCString() },
            })
          : defaults.metno(url, headers),
    });
    await withEnv({}, async () => {
      const first = await answer([OSLO]);
      expect(calls[0]?.headers.has('if-modified-since')).toBe(false);

      // Still within Expires: no call.
      vi.setSystemTime(NOW + 29 * 60_000);
      await answer([OSLO]);
      expect(calls).toHaveLength(1);

      // Past it: a conditional request, and the 304 keeps the forecast.
      vi.setSystemTime(NOW + 31 * 60_000);
      expect(await answer([OSLO])).toEqual(first);
      expect(calls).toHaveLength(2);
      expect(calls[1]?.headers.get('if-modified-since')).toBe(LAST_MODIFIED);

      // The 304's Expires made it fresh again.
      await answer([OSLO]);
      expect(calls).toHaveLength(2);
    });
  });

  it('keeps a MET answer at least 10 minutes whatever Expires says', async () => {
    const calls = stubUpstream({
      metno: () =>
        jsonReply(fixture('metno-complete.json'), 200, {
          expires: new Date(Date.now() - 60_000).toUTCString(),
        }),
    });
    await withEnv({}, async () => {
      await answer([TOKYO]);
      vi.setSystemTime(NOW + 9 * 60_000);
      await answer([TOKYO]);
      expect(calls).toHaveLength(1);
      vi.setSystemTime(NOW + 11 * 60_000);
      await answer([TOKYO]);
      expect(calls).toHaveLength(2);
    });
  });

  it('keeps at most 8 MET calls in flight per worker', async () => {
    let active = 0;
    let peak = 0;
    stubUpstream({
      metno: async (url, headers) => {
        active += 1;
        peak = Math.max(peak, active);
        await new Promise((resolve) => setTimeout(resolve, 10));
        active -= 1;
        return defaults.metno(url, headers);
      },
    });
    await withEnv({}, async () => {
      // Two requests of ten different MET points, six cells at a time each.
      const cells = (offset: number) =>
        Array.from({ length: 10 }, (_, i) => ({ lat: 10 + offset + i, lon: 100 }));
      const [a, b] = await Promise.all([answer(cells(0)), answer(cells(20))]);
      expect(a.cells.every((c) => c.source === 'metno')).toBe(true);
      expect(b.cells.every((c) => c.source === 'metno')).toBe(true);
    });
    expect(peak).toBe(8);
    expect(metnoInFlight()).toBe(0);
  });
});

describe('POST /weather: logging', () => {
  it('logs counts, never coordinates', async () => {
    stubUpstream({ points: () => jsonReply('{}', 404) });
    const lines: string[] = [];
    await withEnv({}, async () => {
      injectSingletons({
        logger: pino({ level: 'debug', base: {} }, { write: (line: string) => lines.push(line) }),
      });
      await answer([NYC, BERLIN, OSLO, TOKYO]);
      await answer([NYC, BERLIN, OSLO, TOKYO]);
    });
    // The request id is random hex and the time is digits: neither is a place.
    const entries = lines.map((l) => JSON.parse(l) as Record<string, unknown>);
    const text = JSON.stringify(entries.map(({ reqId: _id, time: _t, ...rest }) => rest));
    expect(text).toContain('weather answered');
    expect(text).toContain('"nws:404":1');
    for (const value of ['40.75', '-74', '52.525', '13.4', '59.925', '10.75', '35.6', '139.7', '35.7']) {
      expect(text).not.toContain(value);
    }
    const second = entries[1];
    expect(second?.misses).toBe(0);
    expect(second?.hits).toBe(6);
  });
});
