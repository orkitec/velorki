// SPDX-License-Identifier: AGPL-3.0-only
import { z } from 'zod';
import { clientIp } from '@/config';
import { json, withApi } from '@/server/api';
import { WEATHER_BODY_LIMIT, readJsonBody } from '@/server/body';
import { ApiError } from '@/server/errors';
import { requireEntitlement } from '@/server/entitlement';
import { LIMITS, enforce } from '@/server/ratelimit';
import { getConfig, getCounters, getEntitlement } from '@/server/singletons';
import { forecast, providersFor } from '@/weather/forecast';
import { HOUR_MS } from '@/weather/time';
import { userAgent } from '@/weather/upstream';
import type { WeatherContext } from '@/weather/types';

const MAX_CELLS = 150;
const MAX_HOURS = 72;
/** A request may start a little in the past (a ride already under way)... */
const FROM_BEFORE_MS = 3 * HOUR_MS;
/** ...and no further ahead than any provider forecasts. */
const FROM_AFTER_MS = 9 * 24 * HOUR_MS;
/** The whole answer, however many cells: past it the rest count as failed. */
const DEADLINE_MS = 20_000;

/**
 * The app snaps every cell to a 0.025° grid before asking, which is the
 * privacy promise: no position finer than that leaves the phone. A value with
 * more than three decimals means a client that does not keep the promise, and
 * is refused rather than silently rounded.
 */
const atMostThreeDecimals = (v: number) => Math.abs(v * 1000 - Math.round(v * 1000)) < 1e-6;
const coordinate = (min: number, max: number) =>
  z
    .number()
    .min(min)
    .max(max)
    .refine(atMostThreeDecimals, { message: 'must have at most 3 decimals' });

const weatherBodySchema = z.object({
  from: z.iso
    .datetime()
    .refine(
      (v) => {
        const at = Date.parse(v);
        const now = Date.now();
        return at >= now - FROM_BEFORE_MS && at <= now + FROM_AFTER_MS;
      },
      { message: 'must be between 3 hours ago and 9 days from now' },
    ),
  hours: z.number().int().min(1).max(MAX_HOURS),
  cells: z
    .array(
      z.object({
        lat: coordinate(-90, 90),
        lon: coordinate(-180, 180),
        alt: z.number().int().min(-500).max(9000).optional(),
      }),
    )
    .min(1)
    .max(MAX_CELLS),
});

export const POST = withApi(async (request, ctx) => {
  const config = getConfig();
  const counters = getCounters();
  // Per IP before the body is read, as on /share: the only limit that holds
  // for a caller who has not authenticated yet.
  await enforce(counters, clientIp(config, request.headers), [LIMITS.weatherPerIpHour], ctx.log);
  const raw = await readJsonBody(request, WEATHER_BODY_LIMIT);
  const appUserId = await requireEntitlement(getEntitlement(), request.headers, ctx.log);
  await enforce(counters, appUserId, [LIMITS.weatherPerHour, LIMITS.weatherPerDay], ctx.log);

  if (config.WEATHER_PROVIDERS.length === 0) {
    throw new ApiError('unavailable', 'Weather is not configured on this server.');
  }

  const parsed = weatherBodySchema.safeParse(raw);
  if (!parsed.success) {
    throw new ApiError(
      'invalid_request',
      parsed.error.issues.map((i) => `${i.path.join('.') || '(body)'}: ${i.message}`).join('; '),
    );
  }
  const body = parsed.data;

  const weather: WeatherContext = {
    counters,
    userAgent: userAgent(config.APP_VERSION, config.PUBLIC_BASE_URL, config.WEATHER_CONTACT),
    now: Date.now,
    stats: { hits: 0, misses: 0, upstream: {}, failures: {} },
  };
  const result = await forecast(
    { from: Date.parse(body.from), hours: body.hours, cells: body.cells },
    providersFor(config.WEATHER_PROVIDERS, weather),
    weather,
    AbortSignal.timeout(DEADLINE_MS),
  );

  // Counts only: the cells are where riders are going to be.
  const failed = result.cells.filter((c) => c.source === null).length;
  ctx.log.info(
    { cells: body.cells.length, failed, ...weather.stats },
    'weather answered',
  );
  if (failed === result.cells.length) {
    throw new ApiError('upstream_error', 'No weather provider answered.');
  }
  return json(result);
});
