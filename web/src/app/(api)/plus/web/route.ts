// SPDX-License-Identifier: AGPL-3.0-only
import { createHash } from 'node:crypto';
import { z } from 'zod';
import { clientIp } from '@/config';
import { json, withApi } from '@/server/api';
import { WEATHER_BODY_LIMIT, readJsonBody } from '@/server/body';
import { ApiError } from '@/server/errors';
import { LIMITS, enforce } from '@/server/ratelimit';
import { getConfig, getCounters, getEntitlement } from '@/server/singletons';
import { freshIds, type PlusDevice } from '@/plus/devices';
import { googleDevices } from '@/plus/google';
import { icloudDevices } from '@/plus/icloud';
import { mintPlusToken, plusSubject } from '@/plus/token';

/**
 * Plus in the browser, with no account of ours: the browser signs into the
 * rider's own cloud and hands this route the cloud's token; the relay reads
 * the Plus records the rider's apps wrote there itself (never an id the
 * client sends), asks RevenueCat about each id seen in the last 30 days and
 * answers a signed Plus token good for an hour.
 */

const bodySchema = z.object({
  service: z.enum(['icloud', 'google']),
  token: z.string().min(1).max(4096),
});

export const POST = withApi(async (request, ctx) => {
  const config = getConfig();
  const counters = getCounters();
  await enforce(counters, clientIp(config, request.headers), [LIMITS.plusWebPerIpHour], ctx.log);
  const raw = await readJsonBody(request, WEATHER_BODY_LIMIT);
  const parsed = bodySchema.safeParse(raw);
  if (!parsed.success) {
    throw new ApiError(
      'invalid_request',
      parsed.error.issues.map((i) => `${i.path.join('.') || '(body)'}: ${i.message}`).join('; '),
    );
  }
  const secret = config.PLUS_TOKEN_SECRET;
  if (secret === undefined) {
    throw new ApiError('unavailable', 'Plus on the web is not configured on this server.');
  }
  const { service, token } = parsed.data;
  // The cloud token is a credential: only a hash of it is a key.
  const tokenKey = createHash('sha256').update(token).digest('base64url').slice(0, 22);
  await enforce(counters, `plusweb:${tokenKey}`, [LIMITS.plusWebPerTokenHour], ctx.log);

  const now = Date.now();
  let devices: PlusDevice[];
  let rotated: string | undefined;
  if (service === 'google') {
    devices = await googleDevices(token, undefined, ctx.log);
  } else {
    const result = await icloudDevices(config, token, now, undefined, ctx.log);
    devices = result.devices;
    rotated = result.webAuthToken;
  }
  const extra: Record<string, string> =
    rotated === undefined ? {} : { ck_web_auth_token: rotated };

  const ids = freshIds(devices, now);
  ctx.log.info({ service, devices: devices.length, fresh: ids.length }, 'plus web lookup');
  if (ids.length === 0) {
    return refusal(
      'no_devices',
      'No Velorki app has synced with this cloud in the last 30 days.',
      extra,
    );
  }

  const entitlement = getEntitlement();
  let upstreamFailed = false;
  for (const id of ids) {
    let entitled: boolean;
    try {
      entitled = await entitlement.isEntitled(id, ctx.log);
    } catch (err) {
      if (err instanceof ApiError && err.code === 'unavailable') throw err;
      upstreamFailed = true;
      continue;
    }
    if (entitled) {
      const minted = mintPlusToken(secret, plusSubject(secret, id), now);
      return json({ token: minted.token, expires_at: minted.expiresAt, ...extra });
    }
  }
  if (upstreamFailed) {
    throw new ApiError('upstream_error', 'The entitlement service is unavailable.');
  }
  return refusal(
    'not_subscribed',
    'No Velorki app syncing with this cloud has an active Velorki Plus.',
    extra,
  );
});

/** 403 with a reason, carrying the rotated CloudKit token when there is one. */
function refusal(reason: string, message: string, extra: Record<string, string>): Response {
  const body = new ApiError('not_entitled', message, { reason }).toBody();
  return json({ ...body, ...extra }, 403);
}
