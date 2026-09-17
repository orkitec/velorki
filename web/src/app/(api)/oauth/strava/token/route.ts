// SPDX-License-Identifier: AGPL-3.0-only
import { clientIp, stravaConfigured } from '@/config';
import { json, withApi } from '@/server/api';
import { readJsonBody } from '@/server/body';
import { ApiError } from '@/server/errors';
import { requireEntitlement } from '@/server/entitlement';
import { LIMITS, enforce } from '@/server/ratelimit';
import { assertAllowedRedirect, codeBodySchema, parse, relay, STRAVA_TOKEN_URL } from '@/server/oauth';
import { getConfig, getCounters, getEntitlement } from '@/server/singletons';

export const POST = withApi(async (request, ctx) => {
  const config = getConfig();
  // Order preserved from Fastify: the body is parsed before any preHandler.
  const raw = await readJsonBody(request);
  await requireEntitlement(getEntitlement(), request.headers, ctx.log);
  await enforce(
    getCounters(),
    clientIp(config, request.headers),
    [LIMITS.stravaTokenPerMin, LIMITS.stravaTokenPerDay],
    ctx.log,
  );

  if (!stravaConfigured(config)) {
    throw new ApiError('unavailable', 'Strava is not configured on this server.');
  }
  const body = parse(codeBodySchema, raw);
  assertAllowedRedirect(config, body.redirect_uri);

  const form = new URLSearchParams({
    client_id: config.STRAVA_CLIENT_ID ?? '',
    client_secret: config.STRAVA_CLIENT_SECRET ?? '',
    code: body.code,
    grant_type: 'authorization_code',
  });
  const { status, body: payload } = await relay(config, STRAVA_TOKEN_URL, form);
  return json(payload, status);
});
