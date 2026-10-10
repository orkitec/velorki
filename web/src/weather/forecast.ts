// SPDX-License-Identifier: AGPL-3.0-only
import { dwd } from './dwd';
import { metno } from './metno';
import { nws } from './nws';
import { HOUR_MS, floorHour, isoHour, round } from './time';
import { UpstreamError } from './upstream';
import type { Cell, HourlyPoint, Provider, ProviderFactory, Source, WeatherContext } from './types';

/**
 * Every provider this server knows, by the id `WEATHER_PROVIDERS` lists. A new
 * one (WeatherKit) is a module and a line here; the config decides whether and
 * where in the order it runs.
 */
export const PROVIDERS: Record<string, ProviderFactory> = { nws, dwd, metno };

/** The global provider: the fallback for every regional failure. */
export const FALLBACK = 'metno';

/** Cells worked on at once in one request. */
const CELL_CONCURRENCY = 6;

export interface HourOut {
  t: string;
  temp: number;
  wind: number;
  windDir: number;
  gust: number | null;
  precip: number;
  precipProb: number | null;
  cloud: number | null;
}

export interface CellOut {
  source: string | null;
  hours: HourOut[];
}

export interface ForecastOut {
  cells: CellOut[];
  sources: Source[];
}

export interface ForecastQuery {
  /** Epoch ms; the first hour is the full hour at or before it. */
  from: number;
  hours: number;
  cells: Cell[];
}

const orNull = (v: number | null, decimals: number) => (v === null ? null : round(v, decimals));

function window(points: HourlyPoint[], start: number, end: number): HourOut[] {
  return points
    .filter((p) => p.t >= start && p.t < end)
    .map((p) => ({
      t: isoHour(p.t),
      temp: round(p.temp, 1),
      wind: round(p.wind, 1),
      windDir: Math.round(p.windDir) % 360,
      gust: orNull(p.gust, 1),
      precip: round(p.precip, 2),
      precipProb: orNull(p.precipProb, 0),
      cloud: orNull(p.cloud, 0),
    }));
}

function statusOf(err: unknown): string | number {
  if (err instanceof UpstreamError) return err.status;
  return err instanceof Error ? err.name : 'error';
}

/** The ordered providers `ids` names; unknown ids are ignored. */
export function providersFor(ids: readonly string[], ctx: WeatherContext): Provider[] {
  return ids.flatMap((id) => {
    const factory = PROVIDERS[id];
    return factory === undefined ? [] : [factory(ctx)];
  });
}

/**
 * Answer every cell from the first provider that covers it, falling back to
 * MET Norway when that one fails or has no hour in the window. A cell nothing
 * answered comes back with `source: null` and no hours; the caller decides
 * whether that is the whole request failing.
 */
export async function forecast(
  query: ForecastQuery,
  providers: Provider[],
  ctx: WeatherContext,
  signal: AbortSignal,
): Promise<ForecastOut> {
  const start = floorHour(query.from);
  const end = start + query.hours * HOUR_MS;
  const fallback = providers.find((p) => p.id === FALLBACK);
  const fail = (provider: string, status: string | number) => {
    const key = `${provider}:${String(status)}`;
    ctx.stats.failures[key] = (ctx.stats.failures[key] ?? 0) + 1;
  };

  async function answer(cell: Cell): Promise<CellOut> {
    const primary = providers.find((p) => p.covers(cell));
    const tries = [primary, fallback].filter(
      (p, i, all): p is Provider => p !== undefined && all.indexOf(p) === i,
    );
    for (const provider of tries) {
      try {
        const hours = window(await provider.fetch(cell, signal), start, end);
        if (hours.length > 0) return { source: provider.id, hours };
        fail(provider.id, 'no_hours');
      } catch (err) {
        fail(provider.id, statusOf(err));
      }
    }
    return { source: null, hours: [] };
  }

  const cells: CellOut[] = new Array<CellOut>(query.cells.length);
  let next = 0;
  async function worker(): Promise<void> {
    while (next < query.cells.length) {
      const index = next;
      next += 1;
      const cell = query.cells[index];
      if (cell !== undefined) cells[index] = await answer(cell);
    }
  }
  await Promise.all(Array.from({ length: Math.min(CELL_CONCURRENCY, query.cells.length) }, worker));

  const used = new Set(cells.map((c) => c.source));
  const sources = providers.filter((p) => used.has(p.id)).map((p) => p.source);
  return { cells, sources };
}
