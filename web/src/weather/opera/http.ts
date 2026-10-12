// SPDX-License-Identifier: AGPL-3.0-only
import { clientIp } from '@/config';
import type { ApiContext } from '@/server/api';
import { ApiError } from '@/server/errors';
import { requireEntitlement } from '@/server/entitlement';
import { LIMITS, enforce } from '@/server/ratelimit';
import { getConfig, getCounters, getEntitlement, getOpera } from '@/server/singletons';
import type { OperaStore } from './store';

/**
 * The gate both OPERA routes run first, in the relay's order: the per-IP
 * limit, the entitlement, the per-rider limits; then whether this server
 * keeps the radar at all.
 */
export async function operaGate(request: Request, ctx: ApiContext): Promise<OperaStore> {
  const config = getConfig();
  const counters = getCounters();
  await enforce(counters, clientIp(config, request.headers), [LIMITS.radarPerIpHour], ctx.log);
  const appUserId = await requireEntitlement(getEntitlement(), request.headers, ctx.log);
  await enforce(counters, appUserId, [LIMITS.radarPerMin, LIMITS.radarPerDay], ctx.log);
  const store = getOpera();
  if (store === null) {
    throw new ApiError('unavailable', 'The OPERA radar is not configured on this server.');
  }
  return store;
}
