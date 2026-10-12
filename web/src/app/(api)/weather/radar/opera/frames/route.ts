// SPDX-License-Identifier: AGPL-3.0-only
import { json, withApi } from '@/server/api';
import { ApiError } from '@/server/errors';
import { operaGate } from '@/weather/opera/http';
import { OPERA_ATTRIBUTION, OperaUpstreamError } from '@/weather/opera/store';

/**
 * The OPERA radar composite's frames of the last two hours, oldest first, and
 * the newest of them: the app asks no image past it.
 */
export const GET = withApi(async (request, ctx) => {
  const store = await operaGate(request, ctx);
  let frames: number[];
  try {
    frames = await store.frames();
  } catch (err) {
    if (err instanceof OperaUpstreamError) {
      ctx.log.warn({ reason: err.message }, 'opera listing failed');
      throw new ApiError('upstream_error', 'The radar archive did not answer.');
    }
    throw err;
  }
  const iso = frames.map((t) => new Date(t).toISOString());
  return json({
    frames: iso,
    newest: iso.at(-1) ?? null,
    stepMinutes: 5,
    attribution: OPERA_ATTRIBUTION,
  });
});
