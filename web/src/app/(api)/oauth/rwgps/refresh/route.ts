// SPDX-License-Identifier: AGPL-3.0-only
import { withApi } from '@/server/api';
import { ApiError } from '@/server/errors';
import { requireEntitlement } from '@/server/entitlement';
import { getEntitlement } from '@/server/singletons';

/**
 * Ride with GPS access tokens do not expire, so there is nothing to refresh.
 * The route exists so the app gets a structured answer instead of a 404. The
 * request body is documented as optional and is never read.
 */
export const POST = withApi(async (request, ctx) => {
  await requireEntitlement(getEntitlement(), request.headers, ctx.log);
  throw new ApiError(
    'unavailable',
    'Ride with GPS does not support refresh tokens; re-authorize instead.',
    { status: 501 },
  );
});
