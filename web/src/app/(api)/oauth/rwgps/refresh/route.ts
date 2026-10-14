// SPDX-License-Identifier: AGPL-3.0-only
import { withApi } from '@/server/api';
import { ApiError } from '@/server/errors';

/**
 * Ride with GPS access tokens do not expire, so there is nothing to refresh.
 * The route exists so the app gets a structured answer instead of a 404. The
 * request body is documented as optional and is never read.
 */
export const POST = withApi(() => {
  throw new ApiError(
    'unavailable',
    'Ride with GPS does not support refresh tokens; re-authorize instead.',
    { status: 501 },
  );
});
