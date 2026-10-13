// SPDX-License-Identifier: AGPL-3.0-only
import { withApi } from '@/server/api';
import { ApiError } from '@/server/errors';
import { operaGate } from '@/weather/opera/http';
import { OPERA_DOMAIN, MERCATOR_HALF, type MercatorBox } from '@/weather/opera/render';
import { OPERA_STEP_MS, OperaUpstreamError } from '@/weather/opera/store';

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

function parseBox(raw: string | null): MercatorBox {
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
  const [dw, ds, de, dn] = OPERA_DOMAIN;
  if (e <= dw || w >= de || n <= ds || s >= dn) {
    invalid('bbox must meet the OPERA composite.');
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
 * One image of a Web Mercator box at one OPERA frame, the rain in the DWD
 * radar's classes and colours, no data grey, dry and beyond the composite
 * transparent (see `src/weather/opera/render.ts`). The query matches the
 * WMS GetMap the app asks the other radars for: `time`, `bbox` (EPSG:3857),
 * `width`, `height`.
 */
export const GET = withApi(async (request, ctx) => {
  const store = await operaGate(request, ctx);
  const query = new URL(request.url).searchParams;
  const timeRaw = query.get('time');
  const time = timeRaw === null ? NaN : Date.parse(timeRaw);
  if (!Number.isFinite(time) || time % OPERA_STEP_MS !== 0) {
    invalid('time must be an ISO 8601 moment on the five-minute grid.');
  }
  const box = parseBox(query.get('bbox'));
  const width = parseSide('width', query.get('width'));
  const height = parseSide('height', query.get('height'));
  const aspect = (box[2] - box[0]) / width / ((box[3] - box[1]) / height);
  if (aspect > MAX_PIXEL_ASPECT || aspect < 1 / MAX_PIXEL_ASPECT) {
    invalid('width and height must follow the shape of bbox.');
  }

  let png: Buffer;
  try {
    const frames = await store.frames();
    // Only a frame the bucket listed: nothing the client sends reaches a URL.
    if (!frames.includes(time)) invalid('time must be one of the frames listed.');
    png = await store.image(time, box, width, height);
  } catch (err) {
    if (err instanceof OperaUpstreamError) {
      ctx.log.warn({ reason: err.message }, 'opera frame failed');
      throw new ApiError('upstream_error', 'The radar archive did not answer.');
    }
    throw err;
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
