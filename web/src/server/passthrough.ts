// SPDX-License-Identifier: AGPL-3.0-only
import { rwgpsConfigured, stravaConfigured, type Config } from '@/config';
import type { ApiContext } from './api';
import { ApiError } from './errors';
import { requireEntitlement } from './entitlement';
import { LIMITS, enforce } from './ratelimit';
import { getConfig, getCounters, getEntitlement } from './singletons';
import {
  REWRAPPED_HEADER,
  TOKEN_HEADER,
  requireWrapKeys,
  unwrapToken,
  wrapToken,
  type WrappedService,
} from './wrap';

/**
 * Pass-through to Strava and Ride with GPS.
 *
 * The phone calls `/proxy/<service>/<upstream path>` with the relay's own
 * bearer (the RevenueCat id) and the wrapped service token in
 * `X-Velorki-Token`. The relay checks the subscription, refuses anything that
 * is not one of the calls the app makes, unwraps the token in memory, puts it
 * on as `Authorization: Bearer` and streams the body to the service and the
 * answer back, status and all. Nothing is buffered beyond what the network
 * needs and nothing is stored: not the file, not the token, not the answer,
 * and no record of who called what. The per-rider rate-limit windows are the
 * only state a call leaves, and the host's per-route metrics give the totals.
 */

interface UpstreamRoute {
  readonly method: 'GET' | 'POST';
  readonly pattern: RegExp;
  /** The log name; no ids, so a line names the kind of call, never the call. */
  readonly operation: string;
  /**
   * The call authenticates with the client secret rather than the bearer:
   * the relay writes the body itself (`client_id`, `client_secret`, `token`)
   * and ignores whatever the phone sent, so the secret never leaves here and
   * the phone never has to know the shape.
   */
  readonly clientCredentials?: true;
}

interface Upstream {
  /** Origin only; the path after `/proxy/<service>` is appended as it came. */
  readonly base: string;
  readonly label: string;
  readonly routes: readonly UpstreamRoute[];
}

/**
 * Exactly the calls `app/lib/features/integrations` makes, nothing else. Ids
 * are digits on both services. Strava's API host moves to
 * `api-v3.strava.com` on 2027-01-04; that is this one constant.
 */
export const UPSTREAMS: Readonly<Record<WrappedService, Upstream>> = {
  strava: {
    base: 'https://www.strava.com',
    label: 'Strava',
    routes: [
      { method: 'POST', pattern: /^\/api\/v3\/uploads$/, operation: 'upload' },
      { method: 'GET', pattern: /^\/api\/v3\/uploads\/[0-9]+$/, operation: 'upload_status' },
      { method: 'GET', pattern: /^\/api\/v3\/athletes\/[0-9]+\/routes$/, operation: 'list_routes' },
      { method: 'GET', pattern: /^\/api\/v3\/routes\/[0-9]+\/export_gpx$/, operation: 'route_gpx' },
      { method: 'POST', pattern: /^\/oauth\/deauthorize$/, operation: 'deauthorize' },
    ],
  },
  rwgps: {
    base: 'https://ridewithgps.com',
    label: 'Ride with GPS',
    routes: [
      { method: 'GET', pattern: /^\/api\/v1\/users\/current\.json$/, operation: 'user' },
      { method: 'POST', pattern: /^\/api\/v1\/routes\.json$/, operation: 'upload_route' },
      { method: 'POST', pattern: /^\/api\/v1\/trips\.json$/, operation: 'upload_trip' },
      { method: 'GET', pattern: /^\/api\/v1\/tasks\/[0-9]+\.json$/, operation: 'task' },
      { method: 'GET', pattern: /^\/api\/v1\/routes\.json$/, operation: 'list_routes' },
      { method: 'GET', pattern: /^\/api\/v1\/trips\.json$/, operation: 'list_trips' },
      { method: 'GET', pattern: /^\/api\/v1\/routes\/[0-9]+\.gpx$/, operation: 'route_gpx' },
      // Disconnect: Ride with GPS revokes with the client secret, which only
      // the relay has (https://ridewithgps.com/api/v1/doc/authentication).
      {
        method: 'POST',
        pattern: /^\/oauth\/revoke\.json$/,
        operation: 'revoke',
        clientCredentials: true,
      },
    ],
  },
};

/** The client id and secret for [service], or undefined when unconfigured. */
function clientCredentialsFor(
  config: Config,
  service: WrappedService,
): { id: string; secret: string } | undefined {
  if (service === 'strava') {
    if (!stravaConfigured(config)) return undefined;
    return { id: config.STRAVA_CLIENT_ID ?? '', secret: config.STRAVA_CLIENT_SECRET ?? '' };
  }
  if (!rwgpsConfigured(config)) return undefined;
  return { id: config.RWGPS_CLIENT_ID ?? '', secret: config.RWGPS_CLIENT_SECRET ?? '' };
}

/** A FIT or GPX of a long ride is a few megabytes; this is a sanity bound. */
export const PROXY_BODY_LIMIT = 25 * 1024 * 1024;
/** Strava can take a while to accept a large multipart upload. */
const UPSTREAM_TIMEOUT_MS = 60_000;

/** Request headers that go upstream. Everything else stays here. */
const FORWARDED_REQUEST_HEADERS = ['content-type', 'content-length', 'accept'];
/** Response headers that come back. Cookies and the like do not. */
const FORWARDED_RESPONSE_HEADERS = [
  'content-type',
  'content-length',
  'content-disposition',
  'retry-after',
  'x-ratelimit-limit',
  'x-ratelimit-usage',
  'x-readratelimit-limit',
  'x-readratelimit-usage',
];
/** Query parameters that never go upstream: a token in a URL ends up in logs. */
const DROPPED_QUERY = ['access_token'];

/** The upstream path of a request, i.e. what follows `/proxy/<service>`. */
export function upstreamPath(pathname: string, service: WrappedService): string | undefined {
  const marker = `/proxy/${service}/`;
  const at = pathname.indexOf(marker);
  if (at === -1) return undefined;
  const rest = pathname.slice(at + marker.length - 1);
  return rest.length > 1 ? rest.replace(/\/+$/, '') : undefined;
}

export function matchUpstream(
  service: WrappedService,
  method: string,
  path: string,
): UpstreamRoute | undefined {
  const verb = method.toUpperCase();
  return UPSTREAMS[service].routes.find((r) => r.method === verb && r.pattern.test(path));
}

/** `TimeoutError`, `AbortError` or the socket code behind a `fetch failed`. */
function failureReason(err: unknown): string {
  if (!(err instanceof Error)) return 'error';
  const cause = (err as { cause?: { code?: unknown } }).cause;
  const code = cause?.code;
  return typeof code === 'string' ? `${err.name}/${code}` : err.name;
}

/** Fail the stream, and therefore the upstream request, past `limit` bytes. */
function bounded(
  body: ReadableStream<Uint8Array>,
  limit: number,
  onTooLarge: () => void,
): ReadableStream<Uint8Array> {
  let total = 0;
  return body.pipeThrough(
    new TransformStream<Uint8Array, Uint8Array>({
      transform(chunk, controller) {
        total += chunk.byteLength;
        if (total > limit) {
          onTooLarge();
          controller.error(new Error('body too large'));
          return;
        }
        controller.enqueue(chunk);
      },
    }),
  );
}

/**
 * The handler behind `/proxy/strava/*` and `/proxy/rwgps/*`.
 *
 * Order: the subscription first, because an unentitled caller learns nothing
 * about which upstream paths exist; then the allowlist; then the per-rider
 * limit, so a refused path is not charged; then the token, so a bad token is
 * reported as such and not as a service error.
 */
export async function forward(
  request: Request,
  ctx: ApiContext,
  service: WrappedService,
): Promise<Response> {
  const config = getConfig();
  const counters = getCounters();
  const upstream = UPSTREAMS[service];
  const url = new URL(request.url);
  const path = upstreamPath(url.pathname, service);

  const appUserId = await requireEntitlement(getEntitlement(), request.headers, ctx.log);
  const route = path === undefined ? undefined : matchUpstream(service, request.method, path);
  if (route === undefined || path === undefined) {
    throw new ApiError('not_found', `No route for ${request.method} ${url.pathname}.`);
  }
  await enforce(counters, appUserId, [LIMITS.proxyPerMin, LIMITS.proxyPerDay], ctx.log);

  const keys = requireWrapKeys(config.TOKEN_WRAP_KEYS);
  const wrapped = request.headers.get(TOKEN_HEADER);
  if (wrapped === null || wrapped.trim() === '') {
    throw new ApiError('invalid_request', `The ${TOKEN_HEADER} header is required.`);
  }
  const { token, stale } = unwrapToken(keys, service, 'access', wrapped.trim());

  const declared = Number(request.headers.get('content-length') ?? '0');
  if (Number.isFinite(declared) && declared > PROXY_BODY_LIMIT) {
    throw new ApiError('invalid_request', 'Request body is too large.');
  }

  const target = new URL(upstream.base + path);
  for (const [name, value] of url.searchParams) {
    if (!DROPPED_QUERY.includes(name)) target.searchParams.append(name, value);
  }
  const headers = new Headers();
  headers.set('user-agent', `velorki-relay/${config.APP_VERSION}`);
  let tooLarge = false;
  let body: BodyInit | undefined;
  if (route.clientCredentials) {
    const credentials = clientCredentialsFor(config, service);
    if (credentials === undefined) {
      throw new ApiError('unavailable', `${upstream.label} is not configured on this server.`);
    }
    headers.set('content-type', 'application/json');
    headers.set('accept', 'application/json');
    body = JSON.stringify({ client_id: credentials.id, client_secret: credentials.secret, token });
  } else {
    for (const name of FORWARDED_REQUEST_HEADERS) {
      const value = request.headers.get(name);
      if (value !== null) headers.set(name, value);
    }
    headers.set('authorization', `Bearer ${token}`);
    if (request.method === 'POST' && request.body !== null) {
      body = bounded(request.body, PROXY_BODY_LIMIT, () => {
        tooLarge = true;
      });
    }
  }

  const started = Date.now();
  let res: Response;
  try {
    res = await fetch(target, {
      method: request.method,
      headers,
      body,
      // A streamed request body needs this, and lib.dom does not know it yet.
      duplex: 'half',
      signal: AbortSignal.any([request.signal, AbortSignal.timeout(UPSTREAM_TIMEOUT_MS)]),
    } as RequestInit);
  } catch (err) {
    if (tooLarge) throw new ApiError('invalid_request', 'Request body is too large.');
    if (request.signal.aborted) throw new ApiError('upstream_error', 'The request was cancelled.');
    // The error's name and the socket's code, never its message: undici puts
    // the URL in there, and a message is the one place a token could leak.
    ctx.log.warn(
      { service, operation: route.operation, reason: failureReason(err) },
      'upstream unreachable',
    );
    throw new ApiError('upstream_error', `Could not reach ${upstream.label}.`);
  }

  ctx.log.info(
    { service, operation: route.operation, status: res.status, ms: Date.now() - started },
    'forwarded',
  );

  const out = new Headers();
  for (const name of FORWARDED_RESPONSE_HEADERS) {
    const value = res.headers.get(name);
    if (value !== null) out.set(name, value);
  }
  if (stale) out.set(REWRAPPED_HEADER, wrapToken(keys, service, 'access', token));
  return new Response(res.body, { status: res.status, headers: out });
}
