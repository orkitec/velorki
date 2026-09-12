// SPDX-License-Identifier: AGPL-3.0-only
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../app.js';
import { rwgpsConfigured, stravaConfigured, type Config } from '../config.js';
import { ApiError } from '../plugins/errors.js';
import { clientIp, rateLimit } from '../plugins/ratelimit.js';
import { requireEntitlement } from '../plugins/entitlement.js';
import { LIMITS } from '../util/tokenbucket.js';

/**
 * OAuth token relay.
 *
 * The whole reason this service exists: the client secrets of Strava and
 * Ride with GPS must not ship inside an open-source mobile app. The app does
 * the browser part of the OAuth dance and posts the resulting `code` here; we
 * add the secret, call the provider and hand back its answer untouched, so the
 * app keeps owning the tokens and we never store them.
 */

const STRAVA_TOKEN_URL = 'https://www.strava.com/oauth/token';
const RWGPS_TOKEN_URL = 'https://ridewithgps.com/oauth/token.json';
const UPSTREAM_TIMEOUT_MS = 10_000;

const codeBodySchema = z.object({
  code: z.string().min(1).max(512),
  redirect_uri: z.string().min(1).max(2048),
});

const refreshBodySchema = z.object({
  refresh_token: z.string().min(1).max(2048),
});

/**
 * The redirect_uri is forwarded to the provider and therefore decides where a
 * stolen code could be sent. Only exact matches from the allowlist are
 * accepted — no prefix or wildcard matching.
 */
function assertAllowedRedirect(config: Config, redirectUri: string): void {
  if (!config.OAUTH_REDIRECT_ALLOWLIST.includes(redirectUri)) {
    throw new ApiError('invalid_request', 'redirect_uri is not allowed.');
  }
}

/** Remove anything secret-looking from an upstream message before it is echoed. */
function scrub(text: string, config: Config): string {
  let out = text;
  for (const secret of [config.STRAVA_CLIENT_SECRET, config.RWGPS_CLIENT_SECRET]) {
    if (secret !== undefined && secret.length > 0) out = out.split(secret).join('[redacted]');
  }
  return out.slice(0, 500);
}

interface UpstreamResult {
  status: number;
  body: unknown;
  text: string;
}

async function postForm(url: string, form: URLSearchParams): Promise<UpstreamResult> {
  let res: Response;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/x-www-form-urlencoded',
        accept: 'application/json',
      },
      body: form.toString(),
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  } catch {
    throw new ApiError('upstream_error', 'Could not reach the provider.');
  }

  const text = await res.text();
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    body = undefined;
  }
  return { status: res.status, body, text };
}

/** Best-effort human-readable error out of whatever the provider returned. */
function upstreamMessage(result: UpstreamResult): string {
  const body = result.body as { message?: unknown; error?: unknown; error_description?: unknown };
  for (const candidate of [body?.error_description, body?.message, body?.error]) {
    if (typeof candidate === 'string' && candidate.trim() !== '') return candidate.trim();
  }
  return result.text.trim() === '' ? `Provider responded with ${result.status}.` : result.text;
}

export function registerOAuthRoutes(app: FastifyInstance, ctx: AppContext): void {
  const { config } = ctx;
  const entitled = requireEntitlement(ctx.entitlement);
  const byIp = (req: FastifyRequest): string => clientIp(req, config.TRUST_PROXY);

  /** Shared tail of every token exchange: call the provider, pass the answer on. */
  async function relay(url: string, form: URLSearchParams): Promise<{ status: number; body: unknown }> {
    const result = await postForm(url, form);
    if (result.status < 200 || result.status >= 300) {
      // Never leak the client secret, even if the provider echoed it back.
      throw new ApiError('upstream_error', scrub(upstreamMessage(result), config));
    }
    if (result.body === undefined) {
      throw new ApiError('upstream_error', 'Provider returned a non-JSON response.');
    }
    return { status: result.status, body: result.body };
  }

  /* ---------------------------------------------------------------- Strava */

  app.post(
    '/oauth/strava/token',
    {
      preHandler: [
        entitled,
        rateLimit(ctx.limiter, [LIMITS.stravaTokenPerMin, LIMITS.stravaTokenPerDay], byIp),
      ],
    },
    async (req, reply) => {
      if (!stravaConfigured(config)) {
        throw new ApiError('unavailable', 'Strava is not configured on this server.');
      }
      const body = parse(codeBodySchema, req.body);
      assertAllowedRedirect(config, body.redirect_uri);

      const form = new URLSearchParams({
        client_id: config.STRAVA_CLIENT_ID ?? '',
        client_secret: config.STRAVA_CLIENT_SECRET ?? '',
        code: body.code,
        grant_type: 'authorization_code',
      });
      const { status, body: payload } = await relay(STRAVA_TOKEN_URL, form);
      return reply.code(status).send(payload);
    },
  );

  app.post(
    '/oauth/strava/refresh',
    {
      preHandler: [entitled, rateLimit(ctx.limiter, [LIMITS.stravaRefreshPerHour], byIp)],
    },
    async (req, reply) => {
      if (!stravaConfigured(config)) {
        throw new ApiError('unavailable', 'Strava is not configured on this server.');
      }
      const body = parse(refreshBodySchema, req.body);
      const form = new URLSearchParams({
        client_id: config.STRAVA_CLIENT_ID ?? '',
        client_secret: config.STRAVA_CLIENT_SECRET ?? '',
        refresh_token: body.refresh_token,
        grant_type: 'refresh_token',
      });
      const { status, body: payload } = await relay(STRAVA_TOKEN_URL, form);
      return reply.code(status).send(payload);
    },
  );

  /* ----------------------------------------------------------- Ride with GPS */

  app.post(
    '/oauth/rwgps/token',
    {
      preHandler: [
        entitled,
        rateLimit(ctx.limiter, [LIMITS.rwgpsTokenPerMin, LIMITS.rwgpsTokenPerDay], byIp),
      ],
    },
    async (req, reply) => {
      if (!rwgpsConfigured(config)) {
        throw new ApiError('unavailable', 'Ride with GPS is not configured on this server.');
      }
      const body = parse(codeBodySchema, req.body);
      assertAllowedRedirect(config, body.redirect_uri);

      const form = new URLSearchParams({
        client_id: config.RWGPS_CLIENT_ID ?? '',
        client_secret: config.RWGPS_CLIENT_SECRET ?? '',
        code: body.code,
        grant_type: 'authorization_code',
        redirect_uri: body.redirect_uri,
      });
      const { status, body: payload } = await relay(RWGPS_TOKEN_URL, form);
      return reply.code(status).send(payload);
    },
  );

  // Ride with GPS access tokens do not expire, so there is nothing to refresh.
  // The route exists so the app gets a structured answer instead of a 404.
  app.post('/oauth/rwgps/refresh', { preHandler: [entitled] }, async () => {
    throw new ApiError(
      'unavailable',
      'Ride with GPS does not support refresh tokens; re-authorize instead.',
      { status: 501 },
    );
  });
}

/** Run a zod schema over an unknown body and turn failures into invalid_request. */
function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const result = schema.safeParse(body);
  if (!result.success) {
    const detail = result.error.issues
      .map((i) => `${i.path.join('.') || '(body)'}: ${i.message}`)
      .join('; ');
    throw new ApiError('invalid_request', detail);
  }
  return result.data;
}
