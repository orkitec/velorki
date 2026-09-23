// SPDX-License-Identifier: AGPL-3.0-only
import { withApi } from '@/server/api';
import { forward } from '@/server/passthrough';

/** Pass-through to Ride with GPS; the allowlist is in `server/passthrough.ts`. */
export const GET = withApi((request, ctx) => forward(request, ctx, 'rwgps'));
export const POST = withApi((request, ctx) => forward(request, ctx, 'rwgps'));
