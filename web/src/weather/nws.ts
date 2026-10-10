// SPDX-License-Identifier: AGPL-3.0-only
import { intervalHours } from './time';
import { UpstreamError, cached, readJson, snap, upstreamGet } from './upstream';
import type { Cell, HourlyPoint, Provider, ProviderFactory, WeatherContext } from './types';

/**
 * The US National Weather Service: the National Digital Forecast Database
 * grid behind api.weather.gov, hourly to about seven days.
 *
 * Two calls: `/points` maps a place to its forecast office's grid cell (it
 * never changes, so it is kept a week), and the raw grid data is the forecast
 * itself (kept an hour, keyed by the grid so every cell in it shares it).
 */

const ID = 'nws';
const BASE = 'https://api.weather.gov';
const POINT_TTL_S = 7 * 86_400;
/** A place outside every office's grid stays outside; asking daily is plenty. */
const NO_POINT_TTL_S = 86_400;
const GRID_TTL_S = 3_600;

/** The areas the NWS grids cover: [south, north, west, east]. */
const AREAS: readonly (readonly [number, number, number, number])[] = [
  [24, 50, -125, -66], // contiguous states
  [51, 72, -170, -129], // Alaska
  [18.5, 22.5, -161, -154], // Hawaii
  [17.8, 18.6, -67.5, -65.2], // Puerto Rico
];

type PointEntry = { gridUrl: string } | { none: true };

interface GridValue {
  validTime?: unknown;
  value?: unknown;
}
interface GridSeries {
  uom?: unknown;
  values?: unknown;
}

/** Unit conversions by `uom`; a unit not listed here makes the series unusable. */
const TEMP: Record<string, (v: number) => number> = {
  'wmoUnit:degC': (v) => v,
  'wmoUnit:degF': (v) => ((v - 32) * 5) / 9,
};
const SPEED: Record<string, (v: number) => number> = {
  'wmoUnit:km_h-1': (v) => v / 3.6,
  'wmoUnit:m_s-1': (v) => v,
  'wmoUnit:kn': (v) => v * 0.514444,
};
const ANGLE: Record<string, (v: number) => number> = { 'wmoUnit:degree_(angle)': (v) => v };
const LENGTH: Record<string, (v: number) => number> = {
  'wmoUnit:mm': (v) => v,
  'wmoUnit:m': (v) => v * 1000,
  'wmoUnit:in': (v) => v * 25.4,
};
const PERCENT: Record<string, (v: number) => number> = { 'wmoUnit:percent': (v) => v };

/**
 * One grid series as hour → value. `spread` divides an amount evenly over the
 * hours of its interval (precipitation); everything else holds for each hour.
 */
function series(
  raw: unknown,
  units: Record<string, (v: number) => number>,
  spread = false,
): Map<number, number> {
  const out = new Map<number, number>();
  const s = raw as GridSeries | undefined;
  const convert = typeof s?.uom === 'string' ? units[s.uom] : undefined;
  if (convert === undefined || !Array.isArray(s?.values)) return out;
  for (const entry of s.values as GridValue[]) {
    if (typeof entry.validTime !== 'string' || typeof entry.value !== 'number') continue;
    const hours = intervalHours(entry.validTime);
    const value = convert(entry.value) / (spread ? hours.length : 1);
    for (const t of hours) out.set(t, value);
  }
  return out;
}

/** The grid's `properties` as hourly points; exported for the unit tests. */
export function parseGrid(body: unknown): HourlyPoint[] {
  const p = (body as { properties?: Record<string, unknown> } | null)?.properties;
  if (p === undefined) throw new UpstreamError(ID, 'parse');
  const temp = series(p.temperature, TEMP);
  const wind = series(p.windSpeed, SPEED);
  const windDir = series(p.windDirection, ANGLE);
  const gust = series(p.windGust, SPEED);
  const precip = series(p.quantitativePrecipitation, LENGTH, true);
  const precipProb = series(p.probabilityOfPrecipitation, PERCENT);
  const cloud = series(p.skyCover, PERCENT);

  const points: HourlyPoint[] = [];
  for (const [t, c] of [...temp].sort(([a], [b]) => a - b)) {
    const w = wind.get(t);
    const d = windDir.get(t);
    const r = precip.get(t);
    // An hour without its precipitation amount (past the end of the QPF) is
    // left out rather than reported dry.
    if (w === undefined || d === undefined || r === undefined) continue;
    points.push({
      t,
      temp: c,
      wind: w,
      windDir: d,
      gust: gust.get(t) ?? null,
      precip: r,
      precipProb: precipProb.get(t) ?? null,
      cloud: cloud.get(t) ?? null,
    });
  }
  return points;
}

function covers(cell: Cell): boolean {
  return AREAS.some(
    ([s, n, w, e]) => cell.lat >= s && cell.lat <= n && cell.lon >= w && cell.lon <= e,
  );
}

export const nws: ProviderFactory = (ctx: WeatherContext): Provider => ({
  id: ID,
  source: {
    id: ID,
    name: 'U.S. National Weather Service',
    url: 'https://www.weather.gov',
    licence: 'Forecast data: NOAA National Weather Service, public domain.',
  },
  covers,
  async fetch(cell, signal) {
    const lat = snap(cell.lat, 0.025);
    const lon = snap(cell.lon, 0.025);
    const where = `${String(lat)},${String(lon)}`;
    const pointTtl = (entry: PointEntry) => ('none' in entry ? NO_POINT_TTL_S : POINT_TTL_S);
    const point = await cached<PointEntry>(ctx, `wx:nws:point:${where}`, pointTtl, async () => {
      const res = await upstreamGet(ctx, ID, `${BASE}/points/${where}`, signal, {
        accept: 'application/geo+json',
      });
      // Outside every office's grid (offshore, Canada inside the box).
      if (res.status === 404) return { none: true };
      if (!res.ok) throw new UpstreamError(ID, res.status);
      const body = (await readJson(ID, res)) as { properties?: { forecastGridData?: unknown } };
      const gridUrl = body.properties?.forecastGridData;
      // The next call goes wherever this says: only ever to the NWS itself.
      if (typeof gridUrl !== 'string' || !gridUrl.startsWith(`${BASE}/gridpoints/`)) {
        throw new UpstreamError(ID, 'parse');
      }
      return { gridUrl };
    });
    if ('none' in point) throw new UpstreamError(ID, 404);
    return cached(ctx, `wx:nws:grid:${point.gridUrl}`, GRID_TTL_S, async () => {
      const res = await upstreamGet(ctx, ID, point.gridUrl, signal, {
        accept: 'application/geo+json',
      });
      if (!res.ok) throw new UpstreamError(ID, res.status);
      const points = parseGrid(await readJson(ID, res));
      if (points.length === 0) throw new UpstreamError(ID, 'no_data');
      return points;
    });
  },
});
