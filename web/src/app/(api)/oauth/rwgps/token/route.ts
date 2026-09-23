// SPDX-License-Identifier: AGPL-3.0-only
import { clientIp, rwgpsConfigured } from '@/config';
import { json, withApi } from '@/server/api';
import { readJsonBody } from '@/server/body';
import { ApiError } from '@/server/errors';
import { requireEntitlement } from '@/server/entitlement';
import { LIMITS, enforce } from '@/server/ratelimit';
import { assertAllowedRedirect, codeBodySchema, parse, relay, RWGPS_TOKEN_URL } from '@/server/oauth';
import { getConfig, getCounters, getEntitlement } from '@/server/singletons';
import { requireWrapKeys, wrapTokensIn } from '@/server/wrap';

export const POST = withApi(async (request, ctx) => {
  const config = getConfig();
  const raw = await readJsonBody(request);
  await requireEntitlement(getEntitlement(), request.headers, ctx.log);
  await enforce(
    getCounters(),
    clientIp(config, request.headers),
    [LIMITS.rwgpsTokenPerMin, LIMITS.rwgpsTokenPerDay],
    ctx.log,
  );

  if (!rwgpsConfigured(config)) {
    throw new ApiError('unavailable', 'Ride with GPS is not configured on this server.');
  }
  const keys = requireWrapKeys(config.TOKEN_WRAP_KEYS);
  const body = parse(codeBodySchema, raw);
  assertAllowedRedirect(config, body.redirect_uri);

  const form = new URLSearchParams({
    client_id: config.RWGPS_CLIENT_ID ?? '',
    client_secret: config.RWGPS_CLIENT_SECRET ?? '',
    code: body.code,
    grant_type: 'authorization_code',
    redirect_uri: body.redirect_uri,
  });
  const { status, body: payload } = await relay(config, RWGPS_TOKEN_URL, form);
  return json(wrapTokensIn(payload, keys, 'rwgps'), status);
});
