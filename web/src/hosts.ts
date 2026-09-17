// SPDX-License-Identifier: AGPL-3.0-only
import type { Config } from '@/config';

/**
 * Strict host separation.
 *
 * The API lives on `API_HOST` and nothing else; the website and the share
 * pages live on `SITE_HOST` and nothing else. A request arriving with any other
 * Host is answered 404 without reaching a handler, so a stray DNS name pointed
 * at the origin cannot be used to probe the service.
 */

export type HostRole = 'api' | 'site' | 'unknown';

export interface ResolvedHost {
  role: HostRole;
  /** The path the router should see, with the `/__api` dev prefix removed. */
  pathname: string;
  /** True when `pathname` differs from the request's, i.e. a rewrite is due. */
  rewritten: boolean;
}

/** Header a development client can send instead of using api.localhost. */
export const DEV_HOST_HEADER = 'x-velorki-host';
/** Path prefix that reaches the api role from any host when DEV_HOSTS=1. */
export const DEV_API_PREFIX = '/__api';

/** Host header value without its port, lower-cased, brackets stripped. */
export function normalizeHost(raw: string | null): string {
  if (raw === null) return '';
  let host = raw.trim().toLowerCase();
  if (host.startsWith('[')) {
    // [::1]:8080 -> ::1
    const end = host.indexOf(']');
    return end === -1 ? host.slice(1) : host.slice(1, end);
  }
  host = host.replace(/:\d+$/, '');
  return host;
}

/**
 * Orkify's health check calls `http://localhost:<port>/health` directly and
 * cannot be given a Host header, so a loopback Host is the api role. Caddy
 * always forwards the public Host and the origin only accepts connections from
 * Cloudflare, so nothing else can arrive this way.
 */
export function isLoopbackHost(host: string): boolean {
  return host === 'localhost' || host === '::1' || host === '0.0.0.0' || /^127\./.test(host);
}

export function resolveHost(
  config: Config,
  host: string | null,
  pathname: string,
  headers: Headers,
): ResolvedHost {
  const name = normalizeHost(host);
  const plain: ResolvedHost = { role: 'unknown', pathname, rewritten: false };

  if (config.DEV_HOSTS) {
    // Development: one origin plays both roles, so the api role has to be
    // asked for explicitly and the site is what you get otherwise.
    if (pathname === DEV_API_PREFIX || pathname.startsWith(`${DEV_API_PREFIX}/`)) {
      const stripped = pathname.slice(DEV_API_PREFIX.length) || '/';
      return { role: 'api', pathname: stripped, rewritten: true };
    }
    if (headers.get(DEV_HOST_HEADER)?.trim().toLowerCase() === 'api') {
      return { ...plain, role: 'api' };
    }
    if (name === config.API_HOST || name === 'api.localhost') return { ...plain, role: 'api' };
    if (name === config.SITE_HOST || isLoopbackHost(name)) return { ...plain, role: 'site' };
    return plain;
  }

  if (name === config.API_HOST) return { ...plain, role: 'api' };
  if (isLoopbackHost(name)) return { ...plain, role: 'api' };
  if (name === config.SITE_HOST) return { ...plain, role: 'site' };
  return plain;
}

/**
 * Every (method, path) pair the api host serves. Anything else is the JSON 404
 * that Fastify's notFoundHandler produced, which keeps the app's error handling
 * identical across the migration.
 */
export const API_ROUTES: readonly { method: string; path: string }[] = [
  { method: 'GET', path: '/health' },
  { method: 'HEAD', path: '/health' },
  { method: 'POST', path: '/oauth/strava/token' },
  { method: 'POST', path: '/oauth/strava/refresh' },
  { method: 'POST', path: '/oauth/rwgps/token' },
  { method: 'POST', path: '/oauth/rwgps/refresh' },
  { method: 'POST', path: '/ai/plan' },
  { method: 'POST', path: '/share' },
];

export function isApiRoute(method: string, pathname: string): boolean {
  const path = pathname.length > 1 ? pathname.replace(/\/+$/, '') : pathname;
  return API_ROUTES.some((r) => r.method === method.toUpperCase() && r.path === path);
}

/** 10 base62 characters, as minted by the share store. */
export const SHARE_ID_RE = /^[A-Za-z0-9]{10}$/;

export interface SharePath {
  id: string;
  gpx: boolean;
}

/**
 * Match `/s/<id>` and `/s/<id>.gpx`. Returns null when the path is not a share
 * path at all; returns an invalid id so the caller can answer the JSON 404
 * before the request reaches the page.
 */
export function parseSharePath(pathname: string): SharePath | null {
  const match = /^\/s\/([^/]*?)(\.gpx)?$/.exec(pathname);
  if (match === null) return null;
  return { id: match[1] ?? '', gpx: match[2] !== undefined };
}
