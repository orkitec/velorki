// SPDX-License-Identifier: AGPL-3.0-only
import { clientIp } from '@/config';
import { json, withApi, type ApiContext } from '@/server/api';
import { requireEntitlement } from '@/server/entitlement';
import { ApiError } from '@/server/errors';
import { enforce, type LimitSpec } from '@/server/ratelimit';
import { getConfig, getCounters, getEntitlement } from '@/server/singletons';
import { MERCATOR_HALF, type MercatorBox } from './render';
import { RadarUpstreamError, type RadarStore } from './store';

/** The two routes of one relay radar: its store, and its own limits. */
export interface RadarRoutes {
  store: () => RadarStore<unknown>;
  limits: {
    /** Charged per IP before the entitlement is checked. */
    perIpHour: LimitSpec;
    /** Charged per rider after it. */
    perMin: LimitSpec;
    perDay: LimitSpec;
  };
}

/**
 * The gate a radar's routes run first, in the relay's order: the per-IP
 * limit, the entitlement, the per-rider limits.
 */
export async function radarGate(
  request: Request,
  ctx: ApiContext,
  routes: RadarRoutes,
): Promise<RadarStore<unknown>> {
  const config = getConfig();
  const counters = getCounters();
  const { perIpHour, perMin, perDay } = routes.limits;
  await enforce(counters, clientIp(config, request.headers), [perIpHour], ctx.log);
  const appUserId = await requireEntitlement(getEntitlement(), request.headers, ctx.log);
  await enforce(counters, appUserId, [perMin, perDay], ctx.log);
  return routes.store();
}

/** A publisher's failure as the relay answers it: 502, none of its words. */
function upstream(err: unknown, store: RadarStore<unknown>, ctx: ApiContext, what: string): never {
  if (err instanceof RadarUpstreamError) {
    ctx.log.warn({ reason: err.message }, `${store.source.name} ${what} failed`);
    throw new ApiError('upstream_error', 'The radar archive did not answer.');
  }
  throw err;
}

/**
 * `GET …/frames`: the radar's frames of the last two hours, oldest first,
 * and the newest of them: the app asks no image past it.
 */
export function radarFramesRoute(routes: RadarRoutes) {
  return withApi(async (request, ctx) => {
    const store = await radarGate(request, ctx, routes);
    let frames: number[];
    try {
      frames = await store.frames();
    } catch (err) {
      upstream(err, store, ctx, 'listing');
    }
    const iso = frames.map((t) => new Date(t).toISOString());
    return json({
      frames: iso,
      newest: iso.at(-1) ?? null,
      stepMinutes: store.source.stepMs / 60_000,
      attribution: store.source.attribution,
    });
  });
}

/**
 * The largest side of an image, pixels: the app's soft radar image of a
 * view is at most `radarSoftMaxSide` (1536) a side.
 */
const MAX_SIDE = 1536;

/**
 * How far one pixel's metres across may differ from its metres down: the
 * app sizes an image to its box, with a floor of 64 pixels a side that
 * stretches a thin sliver at a coverage's edge.
 */
const MAX_PIXEL_ASPECT = 32;

function invalid(message: string): never {
  throw new ApiError('invalid_request', message);
}

function parseBox(raw: string | null, domain: MercatorBox, label: string): MercatorBox {
  if (raw === null) invalid('bbox is required.');
  const parts = raw.split(',').map((v) => Number(v));
  if (parts.length !== 4 || parts.some((v) => !Number.isFinite(v))) {
    invalid('bbox must be four numbers: west,south,east,north in EPSG:3857 metres.');
  }
  const [w = 0, s = 0, e = 0, n = 0] = parts;
  const limit = MERCATOR_HALF * 1.0001;
  if ([w, s, e, n].some((v) => Math.abs(v) > limit) || w >= e || s >= n) {
    invalid('bbox must lie inside Web Mercator, west before east, south before north.');
  }
  const [dw, ds, de, dn] = domain;
  if (e <= dw || w >= de || n <= ds || s >= dn) {
    invalid(`bbox must meet the ${label}.`);
  }
  return [w, s, e, n];
}

function parseSide(name: string, raw: string | null): number {
  const v = raw === null ? NaN : Number(raw);
  if (!Number.isInteger(v) || v < 1 || v > MAX_SIDE) {
    invalid(`${name} must be a whole number from 1 to ${String(MAX_SIDE)}.`);
  }
  return v;
}

/**
 * `GET …/image`: one image of a Web Mercator box at one frame, the rain in
 * the DWD radar's classes and colours, no data grey, dry and beyond the
 * composite transparent (see `render.ts`). The query matches the WMS GetMap
 * the app asks the other radars for: `time`, `bbox` (EPSG:3857), `width`,
 * `height`.
 */
export function radarImageRoute(routes: RadarRoutes) {
  return withApi(async (request, ctx) => {
    const store = await radarGate(request, ctx, routes);
    const { source } = store;
    const query = new URL(request.url).searchParams;
    const timeRaw = query.get('time');
    const time = timeRaw === null ? NaN : Date.parse(timeRaw);
    if (!Number.isFinite(time) || time % source.stepMs !== 0) {
      invalid('time must be an ISO 8601 moment on the five-minute grid.');
    }
    const box = parseBox(query.get('bbox'), source.domain, source.label);
    const width = parseSide('width', query.get('width'));
    const height = parseSide('height', query.get('height'));
    const aspect = (box[2] - box[0]) / width / ((box[3] - box[1]) / height);
    if (aspect > MAX_PIXEL_ASPECT || aspect < 1 / MAX_PIXEL_ASPECT) {
      invalid('width and height must follow the shape of bbox.');
    }

    let png: Buffer;
    try {
      const frames = await store.frames();
      // Only a frame the publisher listed: nothing the client sends reaches a URL.
      if (!frames.includes(time)) invalid('time must be one of the frames listed.');
      png = await store.image(time, box, width, height);
    } catch (err) {
      upstream(err, store, ctx, 'frame');
    }
    return new Response(new Uint8Array(png), {
      status: 200,
      headers: {
        'content-type': 'image/png',
        // A frame never changes; the phone keeps its own copy anyway.
        'cache-control': 'private, max-age=3600',
      },
    });
  });
}
