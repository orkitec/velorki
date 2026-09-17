// SPDX-License-Identifier: AGPL-3.0-only
import { notFoundResponse } from '@/server/errors';
import { REQUEST_ID_HEADER, requestIdFrom } from '@/server/requestid';
import { getStore } from '@/server/singletons';
import { gpxFilename } from '@/share/format';
import { isValidShareId } from '@/share/store';

/**
 * The raw GPX behind a share link, reached through the proxy's rewrite of
 * `/s/<id>.gpx`. Unauthenticated: the id is the only capability.
 */
export async function GET(
  request: Request,
  ctx: { params: Promise<{ id: string }> },
): Promise<Response> {
  const requestId = requestIdFrom(request.headers);
  const { id } = await ctx.params;

  // Unknown, malformed and expired ids are all a plain 404.
  const record = isValidShareId(id) ? getStore().get(id) : null;
  if (record === null) {
    return notFoundResponse('No such share.', { [REQUEST_ID_HEADER]: requestId });
  }

  return new Response(record.gpx, {
    status: 200,
    headers: {
      'content-type': 'application/gpx+xml; charset=utf-8',
      'content-disposition': `attachment; filename="${gpxFilename(record.name, record.id)}"`,
      'cache-control': 'public, max-age=3600',
      [REQUEST_ID_HEADER]: requestId,
    },
  });
}
