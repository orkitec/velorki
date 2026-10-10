// SPDX-License-Identifier: AGPL-3.0-only
import type { Counters } from '@/server/counters';

/** One request cell: a grid point the app rounded to 0.025° and 50 m. */
export interface Cell {
  lat: number;
  lon: number;
  alt?: number | undefined;
}

/**
 * One forecast hour, in the units of the contract: °C, m/s at 10 m, degrees
 * the wind comes from, mm and percent. Instant values hold at `t`; `precip`,
 * `precipProb` and `gust` describe the hour that starts at `t`. `t` is epoch
 * ms on a full UTC hour, a number so cache entries stay small.
 */
export interface HourlyPoint {
  t: number;
  temp: number;
  wind: number;
  windDir: number;
  gust: number | null;
  precip: number;
  precipProb: number | null;
  cloud: number | null;
}

/** The attribution the app shows for a provider's data. */
export interface Source {
  id: string;
  name: string;
  url: string;
  licence: string;
}

/**
 * A forecast provider. `fetch` answers with every hour it has for the cell,
 * past the request's window too: the router cuts the window, so one cache
 * entry serves any window. A provider throws on anything it cannot answer;
 * the router then falls back.
 */
export interface Provider {
  readonly id: string;
  readonly source: Source;
  covers(cell: Cell): boolean;
  fetch(cell: Cell, signal: AbortSignal): Promise<HourlyPoint[]>;
}

/** What one /weather request did, for the one log line it writes. */
export interface WeatherStats {
  hits: number;
  misses: number;
  /** Upstream calls per provider id. */
  upstream: Record<string, number>;
  /** Failed answers by `provider:status`; never by place. */
  failures: Record<string, number>;
}

/** Everything a provider needs from the request that created it. */
export interface WeatherContext {
  counters: Counters;
  userAgent: string;
  now: () => number;
  stats: WeatherStats;
}

export type ProviderFactory = (ctx: WeatherContext) => Provider;
