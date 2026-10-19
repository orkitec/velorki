// SPDX-License-Identifier: AGPL-3.0-only

/**
 * CORS for the browser build of the planner (app.velorki.com).
 *
 * Pure functions, applied by `proxy.ts` on the api host only. Only the routes
 * a browser planner calls are listed; `/oauth/*` and `/proxy/*` carry service
 * tokens and stay phone-only. No credentials: the app sends no cookies, so
 * `Access-Control-Allow-Credentials` is never set and the allow-origin is
 * always the one exact origin, never `*`.
 */

interface CorsRoute {
  /** Exact path, or a prefix when it ends in `/`. */
  path: string;
  methods: readonly string[];
}

const CORS_ROUTES: readonly CorsRoute[] = [
  { path: '/health', methods: ['GET', 'HEAD'] },
  { path: '/weather', methods: ['POST'] },
  { path: '/weather/radar/opera/', methods: ['GET'] },
  { path: '/weather/radar/dpc/', methods: ['GET'] },
  { path: '/ai/plan', methods: ['POST'] },
  { path: '/share', methods: ['POST'] },
  { path: '/plus/web', methods: ['POST'] },
];

/** What the app sends to these routes (relay_client.dart). */
const ALLOW_HEADERS = 'Content-Type, Authorization, X-Velorki-Client, X-AI-Consent';
/** What the app reads from the answers. */
const EXPOSE_HEADERS = 'Retry-After, X-Request-Id';
const MAX_AGE_S = '600';

/** The methods a CORS path supports, or null when the path is not one. */
export function corsMethods(pathname: string): readonly string[] | null {
  const path = pathname.length > 1 ? pathname.replace(/\/+$/, '') : pathname;
  for (const route of CORS_ROUTES) {
    if (route.path.endsWith('/')) {
      if (path.startsWith(route.path) && path.length > route.path.length) return route.methods;
    } else if (route.path === path) {
      return route.methods;
    }
  }
  return null;
}

/** The request's Origin when it is on the allow-list, else null. */
export function allowedOrigin(origins: readonly string[], origin: string | null): string | null {
  if (origin === null || origin === '') return null;
  return origins.includes(origin) ? origin : null;
}

/**
 * Headers for an OPTIONS preflight, or null when this is not a preflight the
 * relay answers (path not a CORS route, origin not allowed). The caller then
 * treats it as any other unknown request.
 */
export function preflightHeaders(
  origins: readonly string[],
  pathname: string,
  origin: string | null,
): Record<string, string> | null {
  const allowed = allowedOrigin(origins, origin);
  const methods = corsMethods(pathname);
  if (allowed === null || methods === null) return null;
  return {
    'access-control-allow-origin': allowed,
    'access-control-allow-methods': [...methods, 'OPTIONS'].join(', '),
    'access-control-allow-headers': ALLOW_HEADERS,
    'access-control-max-age': MAX_AGE_S,
    vary: 'Origin',
  };
}

/**
 * Add the CORS headers of an actual response, in place. A no-op for a path
 * that is not a CORS route or an origin that is not allowed.
 */
export function applyCors(
  response: { headers: Headers },
  origins: readonly string[],
  pathname: string,
  origin: string | null,
): void {
  const allowed = allowedOrigin(origins, origin);
  if (allowed === null || corsMethods(pathname) === null) return;
  response.headers.set('access-control-allow-origin', allowed);
  response.headers.set('access-control-expose-headers', EXPOSE_HEADERS);
  const vary = (response.headers.get('vary') ?? '')
    .split(',')
    .map((v) => v.trim())
    .filter((v) => v !== '');
  if (!vary.some((v) => v.toLowerCase() === 'origin' || v === '*')) vary.push('Origin');
  response.headers.set('vary', vary.join(', '));
}
