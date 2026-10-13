// SPDX-License-Identifier: AGPL-3.0-only
import { clientIp } from '@/config';
import type { ApiContext } from '@/server/api';
import { requireEntitlement } from '@/server/entitlement';
import { LIMITS, enforce } from '@/server/ratelimit';
import { getConfig, getCounters, getEntitlement, getOpera } from '@/server/singletons';
import type { OperaStore } from './store';

/**
 * The gate both OPERA routes run first, in the relay's order: the per-IP
 * limit, the entitlement, the per-rider limits.
 */
export async function operaGate(request: Request, ctx: ApiContext): Promise<OperaStore> {
  const config = getConfig();
  const counters = getCounters();
  await enforce(counters, clientIp(config, request.headers), [LIMITS.radarPerIpHour], ctx.log);
  const appUserId = await requireEntitlement(getEntitlement(), request.headers, ctx.log);
  await enforce(counters, appUserId, [LIMITS.radarPerMin, LIMITS.radarPerDay], ctx.log);
  return getOpera();
}
