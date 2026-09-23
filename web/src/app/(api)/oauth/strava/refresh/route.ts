// SPDX-License-Identifier: AGPL-3.0-only
import { clientIp, stravaConfigured } from '@/config';
import { json, withApi } from '@/server/api';
import { readJsonBody } from '@/server/body';
import { ApiError } from '@/server/errors';
import { requireEntitlement } from '@/server/entitlement';
import { LIMITS, enforce } from '@/server/ratelimit';
import { parse, refreshBodySchema, relay, STRAVA_TOKEN_URL } from '@/server/oauth';
import { getConfig, getCounters, getEntitlement } from '@/server/singletons';
import { requireWrapKeys, unwrapToken, wrapTokensIn } from '@/server/wrap';

export const POST = withApi(async (request, ctx) => {
  const config = getConfig();
  const raw = await readJsonBody(request);
  await requireEntitlement(getEntitlement(), request.headers, ctx.log);
  await enforce(
    getCounters(),
    clientIp(config, request.headers),
    [LIMITS.stravaRefreshPerHour],
    ctx.log,
  );

  if (!stravaConfigured(config)) {
    throw new ApiError('unavailable', 'Strava is not configured on this server.');
  }
  const keys = requireWrapKeys(config.TOKEN_WRAP_KEYS);
  const body = parse(refreshBodySchema, raw);
  // The refresh token arrives as the phone stored it: wrapped by this relay.
  const { token } = unwrapToken(keys, 'strava', 'refresh', body.refresh_token);
  const form = new URLSearchParams({
    client_id: config.STRAVA_CLIENT_ID ?? '',
    client_secret: config.STRAVA_CLIENT_SECRET ?? '',
    refresh_token: token,
    grant_type: 'refresh_token',
  });
  const { status, body: payload } = await relay(config, STRAVA_TOKEN_URL, form);
  return json(wrapTokensIn(payload, keys, 'strava'), status);
});
