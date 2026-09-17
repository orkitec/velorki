// SPDX-License-Identifier: AGPL-3.0-only
import { NextResponse, type NextRequest } from 'next/server';
import { routing } from '@/i18n/routing';
import { getConfig, getStore } from '@/server/singletons';
import { requestIdFrom, REQUEST_ID_HEADER } from '@/server/requestid';
import { errorBody } from '@/server/errors';
import { isApiRoute, parseSharePath, resolveHost, SHARE_ID_RE } from '@/hosts';

/**
 * The single front door for both hosts.
 *
 * Next 16 calls this file's default export for every matched request, in the
 * Node runtime. It does what the route handlers and pages cannot do for
 * themselves: refuse a request whose Host is neither the api nor the site,
 * answer the api host's JSON 404 for an unknown (method, path), turn
 * `/s/<id>.gpx` into the `/s/<id>/gpx` route while rejecting a malformed id,
 * settle whether a share still exists so the 404 is a real one, and run
 * next-intl's locale negotiation for the website.
 *
 * `cache-control` is only ever set on a response this file *produces*: the
 * JSON errors, the 308, the share page and the rewrite to `/s/gone`. A
 * response a route handler or a page produces keeps its own policy - `withApi`
 * stamps `no-store` on the api host, and the SSE route sends
 * `no-cache, no-transform`.
 */

/**
 * next-intl's middleware is pulled in on first use rather than at module load:
 * the api host never needs it, and its package is published as ESM that only
 * resolves inside a bundler.
 */
let intl: ((request: NextRequest) => NextResponse) | undefined;

async function localeMiddleware(request: NextRequest): Promise<NextResponse> {
  intl ??= (await import('next-intl/middleware')).default(routing);
  return intl(request);
}

/**
 * Site-wide files that exist at one fixed path in one language. They are served
 * as-is: no locale negotiation (a `Vary`-less redirect of `/robots.txt` to
 * `/de/robots.txt` would be a bug), no share handling. They carry a file
 * extension, so the matcher below names them one by one; without that they
 * would skip the proxy entirely and answer 200 on the api host too.
 */
const SITE_FILES = [
  '/robots.txt',
  '/sitemap.xml',
  '/llms.txt',
  '/llms-full.txt',
  '/manifest.webmanifest',
];

/**
 * Where an unknown or expired `/s/<id>` is rewritten. A static page that only
 * calls `notFound()`, so the answer is a real 404 rather than a streamed soft
 * one. Unreachable from outside: `gone` is not a well-formed share id, so a
 * direct request for it gets the JSON 404 below.
 */
const SHARE_GONE_PATH = '/s/gone';

/** Paths the site serves as-is: no locale prefix, no share handling. */
function isPassThrough(pathname: string): boolean {
  return (
    pathname === '/.well-known' ||
    pathname.startsWith('/.well-known/') ||
    pathname.startsWith('/well-known/') ||
    SITE_FILES.includes(pathname)
  );
}

/**
 * Locale negotiation reads `Accept-Language` and the `NEXT_LOCALE` cookie, so
 * the answer to an unprefixed path varies by both: `/` is the English page for
 * one visitor and a 307 to `/de` for another. Without this a shared cache
 * could hand the German redirect to an English reader. Existing entries are
 * kept - next-intl sets one of its own.
 *
 * This survives on the redirect, which is the response that matters: Next
 * replaces `Vary` wholesale on a rendered page with its own RSC list, and
 * neither a proxy header nor a `headers()` rule in next.config can add to it.
 * That is also why docs/DEPLOY_WEB.md forbids Cloudflare's "Cache Everything"
 * on the site host.
 */
function addVary(response: NextResponse, names: readonly string[]): void {
  const present = (response.headers.get('vary') ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter((value) => value !== '');
  const seen = new Set(present.map((value) => value.toLowerCase()));
  for (const name of names) {
    if (seen.has(name.toLowerCase())) continue;
    present.push(name);
    seen.add(name.toLowerCase());
  }
  response.headers.set('vary', present.join(', '));
}

function jsonResponse(status: number, body: unknown, requestId: string): NextResponse {
  return new NextResponse(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      [REQUEST_ID_HEADER]: requestId,
    },
  });
}

/** Forward the settled request id so the handler echoes the same value. */
function forwardHeaders(request: NextRequest, requestId: string): Headers {
  const headers = new Headers(request.headers);
  headers.set(REQUEST_ID_HEADER, requestId);
  return headers;
}

export default async function proxy(request: NextRequest): Promise<NextResponse> {
  const config = getConfig();
  const url = request.nextUrl;
  const requestId = requestIdFrom(request.headers);
  const host = resolveHost(config, request.headers.get('host'), url.pathname, request.headers);

  /* ------------------------------------------------------------- unknown */

  if (host.role === 'unknown') {
    return jsonResponse(404, errorBody('not_found', 'Not found.'), requestId);
  }

  /* ----------------------------------------------------------- api host */

  if (host.role === 'api') {
    // Links handed out before the split still point at the api host.
    const share = parseSharePath(host.pathname);
    if (share !== null) {
      const target = new URL(`https://${config.SITE_HOST}${url.pathname}${url.search}`);
      return NextResponse.redirect(target, {
        status: 308,
        headers: { [REQUEST_ID_HEADER]: requestId, 'cache-control': 'no-store' },
      });
    }

    if (!isApiRoute(request.method, host.pathname)) {
      return jsonResponse(
        404,
        errorBody('not_found', `No route for ${request.method} ${host.pathname}${url.search}.`),
        requestId,
      );
    }

    const headers = forwardHeaders(request, requestId);
    const response = host.rewritten
      ? NextResponse.rewrite(new URL(`${host.pathname}${url.search}`, url), {
          request: { headers },
        })
      : NextResponse.next({ request: { headers } });
    response.headers.set(REQUEST_ID_HEADER, requestId);
    // No `cache-control` here. Setting one on a `next()`/`rewrite()` response
    // overwrites whatever the handler sends, and `POST /ai/plan` must keep its
    // `no-cache, no-transform`. `withApi` already stamps `no-store` on every
    // handler answer that does not bring a policy of its own.
    return response;
  }

  /* ---------------------------------------------------------- site host */

  if (isPassThrough(url.pathname)) {
    const response = NextResponse.next({ request: { headers: forwardHeaders(request, requestId) } });
    response.headers.set(REQUEST_ID_HEADER, requestId);
    return response;
  }

  const share = parseSharePath(url.pathname);
  if (share !== null) {
    if (!SHARE_ID_RE.test(share.id)) {
      // A malformed id never reaches the page or the database.
      return jsonResponse(404, errorBody('not_found', 'No such share.'), requestId);
    }
    const headers = forwardHeaders(request, requestId);
    if (share.gpx) {
      const response = NextResponse.rewrite(new URL(`/s/${share.id}/gpx`, url), {
        request: { headers },
      });
      response.headers.set(REQUEST_ID_HEADER, requestId);
      return response;
    }
    // Whether the share still exists is decided here, not in the page. Under
    // `cacheComponents` every dynamic route streams a static shell first, so a
    // `notFound()` inside the page lands after the 200 has been committed and
    // an expired link would answer "no longer available" with a 200. Next's
    // own guidance is to run the check in the proxy and rewrite to a not-found
    // route; `SHARE_GONE_PATH` is that route. The probe is a single indexed
    // `SELECT 1` in the same process.
    if (!getStore().has(share.id)) {
      const response = NextResponse.rewrite(new URL(SHARE_GONE_PATH, url), {
        request: { headers },
      });
      response.headers.set(REQUEST_ID_HEADER, requestId);
      response.headers.set('cache-control', 'no-store');
      return response;
    }
    const response = NextResponse.next({ request: { headers } });
    response.headers.set(REQUEST_ID_HEADER, requestId);
    // Next overrides a page's own cache headers, so the share page's policy
    // has to be set here.
    response.headers.set('cache-control', 'public, max-age=300');
    return response;
  }

  const response = await localeMiddleware(request);
  response.headers.set(REQUEST_ID_HEADER, requestId);
  // Only the localised pages: the generated site files are one fixed language
  // and the share page is not localised at all.
  addVary(response, ['Accept-Language', 'Cookie']);
  return response;
}

export const config = {
  /**
   * Everything except Next's own static output and any file with an extension
   * — `.gpx` excepted, because `/s/<id>.gpx` is a route this file rewrites, and
   * the generated site files, which are routes of ours and therefore have to
   * pass the host gate like every other route.
   */
  matcher: [
    '/((?!_next/static|_next/image|.*\\.(?!gpx$)[^./]+$).*)',
    '/robots.txt',
    '/sitemap.xml',
    '/llms.txt',
    '/llms-full.txt',
    '/manifest.webmanifest',
  ],
};
