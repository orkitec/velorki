// SPDX-License-Identifier: AGPL-3.0-only
import { HOUR_MS, floorHour, isoHour } from './time';
import { UpstreamError, cached, readJson, snap, upstreamGet } from './upstream';
import type { Cell, HourlyPoint, Provider, ProviderFactory, WeatherContext } from './types';

/**
 * Deutscher Wetterdienst MOSMIX station forecasts, through Bright Sky's JSON
 * API: hourly to ten days, for Germany and the stations around it.
 *
 * The first call for a cell asks by place and learns the nearest forecast
 * station (kept a day); after that the station is asked directly, and its
 * forecast is kept an hour for every cell that resolves to it. The window
 * asked for is always the same, from three hours ago to past the furthest
 * hour a request may want, so one entry serves every request window.
 */

const ID = 'dwd';
const BASE = 'https://api.brightsky.dev/weather';
const STATION_TTL_S = 86_400;
const FORECAST_TTL_S = 3_600;
const MAX_DIST_M = 25_000;
/** From 3 h ago to 9 days plus 72 h ahead: everything a request may ask for. */
const WINDOW_BEFORE_MS = 3 * HOUR_MS;
const WINDOW_AFTER_MS = (9 * 24 + 73) * HOUR_MS;

type StationEntry = { sourceId: number } | { none: true };

interface BrightSkySource {
  id?: unknown;
  observation_type?: unknown;
  distance?: unknown;
}
interface BrightSkyRow {
  timestamp?: unknown;
  source_id?: unknown;
  temperature?: unknown;
  wind_speed?: unknown;
  wind_direction?: unknown;
  wind_gust_speed?: unknown;
  precipitation?: unknown;
  precipitation_probability?: unknown;
  cloud_cover?: unknown;
}
interface BrightSkyBody {
  weather?: BrightSkyRow[];
  sources?: BrightSkySource[];
}

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);

/** The nearest forecast source within reach, or undefined. */
export function forecastSource(body: BrightSkyBody): number | undefined {
  const sources = (body.sources ?? [])
    .filter((s) => s.observation_type === 'forecast' && typeof s.id === 'number')
    .filter((s) => (num(s.distance) ?? 0) <= MAX_DIST_M)
    .sort((a, b) => (num(a.distance) ?? 0) - (num(b.distance) ?? 0));
  const id = sources[0]?.id;
  return typeof id === 'number' ? id : undefined;
}

/**
 * The rows of `sourceId` as hourly points. Bright Sky's precipitation, its
 * probability and the gust describe the hour *before* a row's timestamp, so
 * the hour starting at t takes them from the row at t + 1 h. Speeds are km/h.
 */
export function parseRows(body: BrightSkyBody, sourceId: number): HourlyPoint[] {
  const rows = new Map<number, BrightSkyRow>();
  for (const row of body.weather ?? []) {
    if (row.source_id !== sourceId || typeof row.timestamp !== 'string') continue;
    const t = Date.parse(row.timestamp);
    if (!Number.isNaN(t) && t === floorHour(t)) rows.set(t, row);
  }
  const points: HourlyPoint[] = [];
  for (const t of [...rows.keys()].sort((a, b) => a - b)) {
    const row = rows.get(t);
    const next = rows.get(t + HOUR_MS);
    const temp = num(row?.temperature);
    const wind = num(row?.wind_speed);
    const windDir = num(row?.wind_direction);
    const precip = num(next?.precipitation);
    if (temp === null || wind === null || windDir === null || precip === null) continue;
    const gust = num(next?.wind_gust_speed);
    points.push({
      t,
      temp,
      wind: wind / 3.6,
      windDir,
      gust: gust === null ? null : gust / 3.6,
      precip,
      precipProb: num(next?.precipitation_probability),
      cloud: num(row?.cloud_cover),
    });
  }
  return points;
}

function covers(cell: Cell): boolean {
  return cell.lat >= 45.8 && cell.lat <= 55.1 && cell.lon >= 5.8 && cell.lon <= 17.2;
}

export const dwd: ProviderFactory = (ctx: WeatherContext): Provider => {
  async function get(query: string, signal: AbortSignal): Promise<BrightSkyBody | undefined> {
    const res = await upstreamGet(ctx, ID, `${BASE}?${query}`, signal);
    // Bright Sky answers 404 when no source lies within max_dist.
    if (res.status === 404) return undefined;
    if (!res.ok) throw new UpstreamError(ID, res.status);
    return (await readJson(ID, res)) as BrightSkyBody;
  }

  return {
    id: ID,
    source: {
      id: ID,
      name: 'Deutscher Wetterdienst',
      url: 'https://www.dwd.de',
      licence: 'Forecast data: Deutscher Wetterdienst (DWD), via Bright Sky.',
    },
    covers,
    async fetch(cell, signal) {
      const start = floorHour(ctx.now()) - WINDOW_BEFORE_MS;
      const window = new URLSearchParams({
        date: isoHour(start),
        last_date: isoHour(start + WINDOW_BEFORE_MS + WINDOW_AFTER_MS),
        tz: 'Etc/UTC',
      });
      const forecastKey = (sourceId: number) => `wx:dwd:fc:${String(sourceId)}:${String(start)}`;
      const lat = snap(cell.lat, 0.025);
      const lon = snap(cell.lon, 0.025);

      const station = await cached<StationEntry>(
        ctx,
        `wx:dwd:station:${String(lat)},${String(lon)}`,
        STATION_TTL_S,
        async () => {
          const query = new URLSearchParams({
            lat: String(lat),
            lon: String(lon),
            max_dist: String(MAX_DIST_M),
          });
          const body = await get(`${query.toString()}&${window.toString()}`, signal);
          const sourceId = body === undefined ? undefined : forecastSource(body);
          if (body === undefined || sourceId === undefined) return { none: true };
          // The answer by place already holds the station's forecast.
          const points = parseRows(body, sourceId);
          if (points.length > 0) {
            await ctx.counters.set(forecastKey(sourceId), points, FORECAST_TTL_S);
          }
          return { sourceId };
        },
      );
      if ('none' in station) throw new UpstreamError(ID, 'no_data');

      return cached(ctx, forecastKey(station.sourceId), FORECAST_TTL_S, async () => {
        const query = new URLSearchParams({ source_id: String(station.sourceId) });
        const body = await get(`${query.toString()}&${window.toString()}`, signal);
        const points = body === undefined ? [] : parseRows(body, station.sourceId);
        if (points.length === 0) throw new UpstreamError(ID, 'no_data');
        return points;
      });
    },
  };
};
