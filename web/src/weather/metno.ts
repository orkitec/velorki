// SPDX-License-Identifier: AGPL-3.0-only
import { HOUR_MS, floorHour, lerp, lerpAngle } from './time';
import { UpstreamError, once, readJson, snap, upstreamGet } from './upstream';
import type { Cell, HourlyPoint, Provider, ProviderFactory, WeatherContext } from './types';

/**
 * MET Norway's Locationforecast: the whole globe, hourly to about 60 hours and
 * six-hourly after that to ten days. It answers every cell no regional
 * provider covers and every cell a regional provider failed.
 *
 * MET's terms shape this module: coordinates with at most four decimals, an
 * identifying User-Agent, the cache held until `Expires`, and a stale entry
 * refreshed with `If-Modified-Since` so an unchanged forecast costs a 304.
 */

const ID = 'metno';
const URL_BASE = 'https://api.met.no/weatherapi/locationforecast/2.0/complete';
const MIN_TTL_S = 600;
const MAX_TTL_S = 7_200;
/** A stale entry is kept this long for its `Last-Modified`, never served unchecked. */
const KEEP_S = 86_400;

/**
 * At most this many MET calls in flight per worker. MET allows 20 a second
 * per application; two workers at 8 stay under it however slow MET answers.
 */
const MAX_IN_FLIGHT = 8;
let inFlight = 0;
const waiting: (() => void)[] = [];

async function acquire(): Promise<void> {
  if (inFlight < MAX_IN_FLIGHT) {
    inFlight += 1;
    return;
  }
  // The releasing call hands its slot over, so `inFlight` stays as it is.
  await new Promise<void>((resolve) => waiting.push(resolve));
}

function release(): void {
  const next = waiting.shift();
  if (next === undefined) inFlight -= 1;
  else next();
}

/** Tests only: how many calls hold a slot. */
export function metnoInFlight(): number {
  return inFlight;
}

interface Entry {
  points: HourlyPoint[];
  /** Epoch ms after which the entry has to be revalidated. */
  freshUntil: number;
  lastModified: string | null;
}

/** MEPS, MET's fine Nordic model: there a 0.025° cell differs from its neighbour. */
function inNordicArea(cell: Cell): boolean {
  return cell.lat >= 53 && cell.lat <= 72 && cell.lon >= -1 && cell.lon <= 32;
}

/**
 * The point MET is asked for. Outside the Nordic model the global one is
 * about 0.1° coarse, so finer cells would only split the cache.
 */
export function metnoPoint(cell: Cell): { lat: number; lon: number } {
  const step = inNordicArea(cell) ? 0.025 : 0.1;
  return { lat: snap(cell.lat, step), lon: snap(cell.lon, step) };
}

interface Details {
  air_temperature?: unknown;
  wind_speed?: unknown;
  wind_from_direction?: unknown;
  wind_speed_of_gust?: unknown;
  cloud_area_fraction?: unknown;
  precipitation_amount?: unknown;
  probability_of_precipitation?: unknown;
}
interface Step {
  time?: unknown;
  data?: {
    instant?: { details?: Details };
    next_1_hours?: { details?: Details };
    next_6_hours?: { details?: Details };
  };
}

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);

interface Parsed {
  t: number;
  temp: number;
  wind: number;
  windDir: number;
  gust: number | null;
  cloud: number | null;
  precip1: number | null;
  prob1: number | null;
  precip6: number | null;
  prob6: number | null;
}

/**
 * The timeseries as hourly points. Between six-hourly steps the instant values
 * are interpolated linearly (the direction the short way round) and the six
 * hours' precipitation is split evenly; nothing is invented after the last
 * step, and an hour no precipitation amount covers is left out.
 */
export function parseTimeseries(body: unknown): HourlyPoint[] {
  const raw = (body as { properties?: { timeseries?: Step[] } } | null)?.properties?.timeseries;
  if (!Array.isArray(raw)) throw new UpstreamError(ID, 'parse');
  const steps: Parsed[] = [];
  for (const step of raw) {
    const t = typeof step.time === 'string' ? Date.parse(step.time) : NaN;
    const i = step.data?.instant?.details;
    const temp = num(i?.air_temperature);
    const wind = num(i?.wind_speed);
    const windDir = num(i?.wind_from_direction);
    if (Number.isNaN(t) || t !== floorHour(t)) continue;
    if (temp === null || wind === null || windDir === null) continue;
    const n1 = step.data?.next_1_hours?.details;
    const n6 = step.data?.next_6_hours?.details;
    steps.push({
      t,
      temp,
      wind,
      windDir,
      gust: num(i?.wind_speed_of_gust),
      cloud: num(i?.cloud_area_fraction),
      precip1: num(n1?.precipitation_amount),
      prob1: num(n1?.probability_of_precipitation),
      precip6: num(n6?.precipitation_amount),
      prob6: num(n6?.probability_of_precipitation),
    });
  }
  steps.sort((a, b) => a.t - b.t);

  const points: HourlyPoint[] = [];
  steps.forEach((a, index) => {
    const b = steps[index + 1];
    const span = b === undefined ? 1 : Math.round((b.t - a.t) / HOUR_MS);
    for (let h = 0; h < span; h += 1) {
      const t = a.t + h * HOUR_MS;
      // The hour's own amount when MET gives one, else a sixth of the six
      // hours that started at this step, while they last.
      let precip: number | null = null;
      let precipProb: number | null = null;
      if (h === 0 && a.precip1 !== null) {
        precip = a.precip1;
        precipProb = a.prob1;
      } else if (a.precip6 !== null && h < 6) {
        precip = a.precip6 / 6;
        precipProb = a.prob6;
      }
      if (precip === null) continue;
      const f = h / span;
      const pair = (x: number | null, y: number | null | undefined) =>
        x === null ? null : h === 0 ? x : y === null || y === undefined ? null : lerp(x, y, f);
      points.push({
        t,
        temp: b === undefined ? a.temp : lerp(a.temp, b.temp, f),
        wind: b === undefined ? a.wind : lerp(a.wind, b.wind, f),
        windDir: b === undefined ? a.windDir : lerpAngle(a.windDir, b.windDir, f),
        gust: pair(a.gust, b?.gust),
        precip,
        precipProb,
        cloud: pair(a.cloud, b?.cloud),
      });
    }
  });
  return points;
}

/** Seconds until `Expires`, clamped to [10 min, 2 h]. */
function freshForS(expires: string | null, now: number): number {
  const at = expires === null ? NaN : Date.parse(expires);
  const s = Number.isNaN(at) ? MIN_TTL_S : Math.round((at - now) / 1000);
  return Math.min(MAX_TTL_S, Math.max(MIN_TTL_S, s));
}

export const metno: ProviderFactory = (ctx: WeatherContext): Provider => ({
  id: ID,
  source: {
    id: ID,
    name: 'MET Norway',
    url: 'https://www.met.no/en',
    licence: 'Weather data from MET Norway, CC BY 4.0 and NLOD 2.0.',
  },
  covers: () => true,
  async fetch(cell, signal) {
    const { lat, lon } = metnoPoint(cell);
    const alt = cell.alt === undefined ? '' : String(cell.alt);
    const key = `wx:metno:${String(lat)},${String(lon)},${alt}`;
    const stored = await ctx.counters.get<Entry>(key);
    if (stored !== undefined && stored.freshUntil > ctx.now()) {
      ctx.stats.hits += 1;
      return stored.points;
    }
    ctx.stats.misses += 1;

    return once(key, async () => {
      const query = new URLSearchParams({ lat: String(lat), lon: String(lon) });
      if (cell.alt !== undefined) query.set('altitude', String(cell.alt));
      const headers: Record<string, string> = {};
      if (stored?.lastModified != null) headers['if-modified-since'] = stored.lastModified;

      // The slot is held until the body is read: that is when MET is done.
      await acquire();
      try {
        const res = await upstreamGet(ctx, ID, `${URL_BASE}?${query.toString()}`, signal, headers);
        let points: HourlyPoint[];
        if (res.status === 304 && stored !== undefined) {
          points = stored.points;
        } else if (res.ok) {
          points = parseTimeseries(await readJson(ID, res));
          if (points.length === 0) throw new UpstreamError(ID, 'no_data');
        } else {
          throw new UpstreamError(ID, res.status);
        }
        const now = ctx.now();
        const entry: Entry = {
          points,
          freshUntil: now + freshForS(res.headers.get('expires'), now) * 1000,
          lastModified: res.headers.get('last-modified') ?? stored?.lastModified ?? null,
        };
        await ctx.counters.set(key, entry, KEEP_S);
        return points;
      } finally {
        release();
      }
    });
  },
});
