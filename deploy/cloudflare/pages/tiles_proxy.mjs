// SPDX-License-Identifier: AGPL-3.0-only
//
// The tile mirror under the web app's own origin, so the browser needs no CORS.
//
//   GET /tiles/latest.json
//     -> https://raw.githubusercontent.com/orkitec/velorki-data/main/latest.json
//        with every `baseUrl` (top level and per shard) of the form
//        https://github.com/orkitec/velorki-data/releases/download/<tag>/
//        rewritten to <request origin>/tiles/<tag>/; every other key kept.
//        Cached for five minutes.
//   GET|HEAD /tiles/<tag>/<file>
//     -> https://github.com/orkitec/velorki-data/releases/download/<tag>/<file>
//        (redirect followed), body streamed through. <tag> is tiles-YYYYMMDD
//        with an optional -sN; <file> is <TILE>.rd5, <TILE>.gaz or
//        manifest.json, <TILE> like E5_N45 or W120_S35. A tag's files never
//        change, so full responses are immutable and kept in the edge cache;
//        a Range request goes to the origin and is never cached.
//
// Anything else under /tiles/ is a 404, a method other than GET, HEAD or
// OPTIONS a 405. Nothing of the request but Range reaches the origin.
//
// No Cloudflare globals here: `env` carries fetch, cache (match/put) and
// waitUntil, so the Pages Function wires the real ones and tests fake them.

export const POINTER_URL =
  'https://raw.githubusercontent.com/orkitec/velorki-data/main/latest.json';
export const RELEASES_URL =
  'https://github.com/orkitec/velorki-data/releases/download/';

const TAG = /^tiles-\d{8}(-s\d+)?$/;
const TILE_FILE = /^[EW]\d{1,3}_[NS]\d{1,2}\.(rd5|gaz)$/;
const POINTER_CACHE = 'public, max-age=300';
const FILE_CACHE = 'public, max-age=31536000, immutable';
const ALLOW = 'GET, HEAD, OPTIONS';

/** What a request path names: the pointer, one mirror file, or nothing. */
export function mapPath(pathname) {
  // Encoded characters (%2F, %2e%2e, ...) never belong in a valid path.
  if (pathname.includes('%') || pathname.includes('\\')) return null;
  if (pathname === '/tiles/latest.json') return { kind: 'pointer' };
  const parts = pathname.split('/');
  if (parts.length !== 4 || parts[0] !== '' || parts[1] !== 'tiles') {
    return null;
  }
  const [, , tag, file] = parts;
  if (!TAG.test(tag)) return null;
  if (file !== 'manifest.json' && !TILE_FILE.test(file)) return null;
  return { kind: 'file', tag, file, upstream: `${RELEASES_URL}${tag}/${file}` };
}

/** The pointer with its release URLs moved under `origin`/tiles/. */
export function rewritePointer(json, origin) {
  const rewrite = (url) => {
    if (typeof url !== 'string' || !url.startsWith(RELEASES_URL)) return url;
    const tag = url.slice(RELEASES_URL.length).replace(/\/$/, '');
    return TAG.test(tag) ? `${origin}/tiles/${tag}/` : url;
  };
  const out = { ...json };
  if ('baseUrl' in out) out.baseUrl = rewrite(out.baseUrl);
  if (Array.isArray(out.shards)) {
    out.shards = out.shards.map((shard) =>
      shard && typeof shard === 'object' && 'baseUrl' in shard
        ? { ...shard, baseUrl: rewrite(shard.baseUrl) }
        : shard,
    );
  }
  return out;
}

export async function handleTiles(request, env) {
  const method = request.method;
  if (method !== 'GET' && method !== 'HEAD' && method !== 'OPTIONS') {
    return new Response(null, { status: 405, headers: { Allow: ALLOW } });
  }
  const url = new URL(request.url);
  const target = mapPath(url.pathname);
  if (target === null) return notFound();
  if (method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: { Allow: ALLOW } });
  }
  return target.kind === 'pointer'
    ? pointer(request, url, env)
    : file(request, url, target, env);
}

async function pointer(request, url, env) {
  // The key carries the origin, so each preview deployment caches its own.
  const key = new Request(url.toString(), { method: 'GET' });
  const cached = await env.cache.match(key);
  if (cached) return forMethod(request, cached);

  let upstream;
  try {
    upstream = await env.fetch(POINTER_URL, { redirect: 'follow' });
  } catch {
    return badGateway();
  }
  if (upstream.status === 404) return notFound();
  if (!upstream.ok) return badGateway();
  let json;
  try {
    json = await upstream.json();
  } catch {
    return badGateway();
  }
  const response = new Response(
    JSON.stringify(rewritePointer(json, url.origin)),
    {
      status: 200,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': POINTER_CACHE,
        'X-Content-Type-Options': 'nosniff',
      },
    },
  );
  env.waitUntil(env.cache.put(key, response.clone()));
  return forMethod(request, response);
}

async function file(request, url, target, env) {
  const range = request.headers.get('Range');
  const key = new Request(url.toString(), { method: 'GET' });
  if (range === null) {
    const cached = await env.cache.match(key);
    if (cached) return forMethod(request, cached);
  }

  const headers = new Headers();
  if (range !== null) headers.set('Range', range);
  let upstream;
  try {
    upstream = await env.fetch(target.upstream, {
      method: request.method,
      headers,
      redirect: 'follow',
    });
  } catch {
    return badGateway();
  }

  const status = upstream.status;
  if (status === 404) return notFound();
  const passable =
    status === 200 || (range !== null && (status === 206 || status === 416));
  if (!passable) return badGateway();

  const out = new Headers({
    'Content-Type':
      target.file === 'manifest.json'
        ? 'application/json; charset=utf-8'
        : 'application/octet-stream',
    'Cache-Control': FILE_CACHE,
    'Accept-Ranges': 'bytes',
    'X-Content-Type-Options': 'nosniff',
  });
  for (const name of ['Content-Length', 'Content-Range', 'ETag', 'Last-Modified']) {
    const value = upstream.headers.get(name);
    if (value !== null) out.set(name, value);
  }
  const response = new Response(request.method === 'HEAD' ? null : upstream.body, {
    status,
    headers: out,
  });
  if (range === null && request.method === 'GET' && status === 200) {
    env.waitUntil(env.cache.put(key, response.clone()));
  }
  return response;
}

function forMethod(request, response) {
  if (request.method !== 'HEAD') return response;
  return new Response(null, { status: response.status, headers: response.headers });
}

function notFound() {
  return new Response('Not found\n', {
    status: 404,
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
}

function badGateway() {
  return new Response('Bad gateway\n', {
    status: 502,
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
}
