// SPDX-License-Identifier: AGPL-3.0-only
//
// node --test deploy/cloudflare/test/

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  handleTiles,
  mapPath,
  rewritePointer,
  POINTER_URL,
} from '../pages/tiles_proxy.mjs';

const ORIGIN = 'https://app.velorki.com';
const RELEASES = 'https://github.com/orkitec/velorki-data/releases/download';

const POINTER = {
  tag: 'tiles-20261001',
  generatedAt: '2026-10-01T10:24:01Z',
  formatVersion: '11.2',
  baseUrl: `${RELEASES}/tiles-20261001/`,
  shardCount: 2,
  shards: [
    { tag: 'tiles-20261001', baseUrl: `${RELEASES}/tiles-20261001/`, tileCount: 480 },
    { tag: 'tiles-20261001-s2', baseUrl: `${RELEASES}/tiles-20261001-s2/`, tileCount: 182 },
  ],
  weatherLayers: { radar: { url: 'https://example.org/{z}/{x}/{y}.png' } },
  tileCount: 662,
};

/** A fetch that records its calls and answers with `respond(url, init)`. */
function fakeFetch(respond) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    calls.push({ url, init });
    return respond(url, init);
  };
  return { fetch, calls };
}

/** A Map-backed stand-in for caches.default, keyed by request URL. */
function fakeCache() {
  const store = new Map();
  return {
    store,
    async match(request) {
      const hit = store.get(request.url);
      return hit ? hit.clone() : undefined;
    },
    async put(request, response) {
      assert.equal(request.method, 'GET');
      const body = await response.arrayBuffer();
      store.set(request.url, new Response(body, response));
    },
  };
}

function setup(respond) {
  const { fetch, calls } = fakeFetch(respond);
  const cache = fakeCache();
  const pending = [];
  const env = { fetch, cache, waitUntil: (p) => pending.push(p) };
  return { env, calls, cache, settle: () => Promise.all(pending) };
}

function bytes(n) {
  return new Uint8Array(n).map((_, i) => i % 251);
}

function fileResponse(body, extra = {}) {
  return new Response(body, {
    status: 200,
    headers: {
      'Content-Type': 'application/octet-stream',
      'Content-Length': String(body.length),
      'Set-Cookie': 'session=upstream',
      ...extra,
    },
  });
}

test('mapPath names the pointer', () => {
  assert.deepEqual(mapPath('/tiles/latest.json'), { kind: 'pointer' });
});

test('mapPath maps rd5, gaz and manifest of a main and an -s2 shard', () => {
  for (const tag of ['tiles-20261001', 'tiles-20261001-s2']) {
    for (const file of ['W20_N30.rd5', 'E005_N45.gaz', 'E0_S10.rd5', 'manifest.json']) {
      assert.deepEqual(mapPath(`/tiles/${tag}/${file}`), {
        kind: 'file',
        tag,
        file,
        upstream: `${RELEASES}/${tag}/${file}`,
      });
    }
  }
});

test('mapPath rejects anything else', () => {
  for (const path of [
    '/tiles/',
    '/tiles/latest.json/',
    '/tiles/foo/W20_N30.rd5',
    '/tiles/tiles-2026100/W20_N30.rd5',
    '/tiles/tiles-20261001-x2/W20_N30.rd5',
    '/tiles/tiles-20261001/evil.js',
    '/tiles/tiles-20261001/W20_N30.rd5.js',
    '/tiles/tiles-20261001/X20_N30.rd5',
    '/tiles/tiles-20261001/W20_N30',
    '/tiles/tiles-20261001/sub/W20_N30.rd5',
    '/tiles/tiles-20261001/..',
    '/tiles/tiles-20261001%2FW20_N30.rd5',
    '/tiles/tiles-20261001/%2e%2e',
    '/tiles/tiles-20261001/W20_N30.rd5%00',
    '/other/tiles-20261001/W20_N30.rd5',
  ]) {
    assert.equal(mapPath(path), null, path);
  }
});

test('rewritePointer moves shard and top-level URLs under the origin', () => {
  const out = rewritePointer(POINTER, 'https://abc.velorki-app.pages.dev');
  assert.equal(out.baseUrl, 'https://abc.velorki-app.pages.dev/tiles/tiles-20261001/');
  assert.deepEqual(
    out.shards.map((s) => s.baseUrl),
    [
      'https://abc.velorki-app.pages.dev/tiles/tiles-20261001/',
      'https://abc.velorki-app.pages.dev/tiles/tiles-20261001-s2/',
    ],
  );
  assert.deepEqual(out.weatherLayers, POINTER.weatherLayers);
  assert.equal(out.shards[1].tileCount, 182);
  assert.equal(out.generatedAt, POINTER.generatedAt);
  assert.equal(out.tileCount, 662);
  // The input is left as it was.
  assert.equal(POINTER.baseUrl, `${RELEASES}/tiles-20261001/`);
});

test('rewritePointer leaves URLs it does not recognise alone', () => {
  const out = rewritePointer(
    { baseUrl: 'https://elsewhere.example/x/', shards: [{ baseUrl: `${RELEASES}/evil/` }] },
    ORIGIN,
  );
  assert.equal(out.baseUrl, 'https://elsewhere.example/x/');
  assert.equal(out.shards[0].baseUrl, `${RELEASES}/evil/`);
});

test('GET /tiles/latest.json serves the rewritten pointer with a short cache', async () => {
  const { env, calls, settle } = setup(
    () => new Response(JSON.stringify(POINTER), { headers: { 'Content-Type': 'text/plain' } }),
  );
  const origin = 'https://preview.velorki-app.pages.dev';
  const res = await handleTiles(new Request(`${origin}/tiles/latest.json`), env);
  await settle();
  assert.equal(res.status, 200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, POINTER_URL);
  assert.match(res.headers.get('Content-Type'), /^application\/json/);
  assert.equal(res.headers.get('Cache-Control'), 'public, max-age=300');
  const body = await res.json();
  assert.equal(body.baseUrl, `${origin}/tiles/tiles-20261001/`);
  assert.equal(body.shards[1].baseUrl, `${origin}/tiles/tiles-20261001-s2/`);
  assert.deepEqual(body.weatherLayers, POINTER.weatherLayers);
});

test('the pointer is served from the edge cache on the second request', async () => {
  const { env, calls, settle } = setup(() => new Response(JSON.stringify(POINTER)));
  await handleTiles(new Request(`${ORIGIN}/tiles/latest.json`), env);
  await settle();
  const res = await handleTiles(new Request(`${ORIGIN}/tiles/latest.json`), env);
  assert.equal(calls.length, 1);
  assert.equal((await res.json()).baseUrl, `${ORIGIN}/tiles/tiles-20261001/`);
});

test('a failing pointer upstream is a 502', async () => {
  const { env } = setup(() => new Response('oops', { status: 500 }));
  const res = await handleTiles(new Request(`${ORIGIN}/tiles/latest.json`), env);
  assert.equal(res.status, 502);
});

test('a file is fetched from its release, redirects followed, streamed, cached', async () => {
  const body = bytes(4096);
  const { env, calls, cache, settle } = setup(() => fileResponse(body, { ETag: '"abc"' }));
  const url = `${ORIGIN}/tiles/tiles-20261001-s2/W20_N30.rd5`;
  const res = await handleTiles(new Request(url), env);
  assert.equal(res.status, 200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, `${RELEASES}/tiles-20261001-s2/W20_N30.rd5`);
  assert.equal(calls[0].init.redirect, 'follow');
  assert.equal(calls[0].init.method, 'GET');
  assert.ok(res.body instanceof ReadableStream);
  assert.equal(res.headers.get('Content-Type'), 'application/octet-stream');
  assert.equal(res.headers.get('Content-Length'), '4096');
  assert.equal(res.headers.get('ETag'), '"abc"');
  assert.equal(res.headers.get('Cache-Control'), 'public, max-age=31536000, immutable');
  assert.equal(res.headers.get('Set-Cookie'), null);
  assert.deepEqual(new Uint8Array(await res.arrayBuffer()), body);
  await settle();
  assert.ok(cache.store.has(url), 'a miss puts the response in the cache via waitUntil');
});

test('a manifest is served as JSON', async () => {
  const { env, calls } = setup(() => new Response('{"tiles":[]}', { status: 200 }));
  const res = await handleTiles(
    new Request(`${ORIGIN}/tiles/tiles-20261001/manifest.json`),
    env,
  );
  assert.equal(calls[0].url, `${RELEASES}/tiles-20261001/manifest.json`);
  assert.match(res.headers.get('Content-Type'), /^application\/json/);
  assert.equal(res.headers.get('Cache-Control'), 'public, max-age=31536000, immutable');
  assert.deepEqual(await res.json(), { tiles: [] });
});

test('a gaz file is served as octet-stream', async () => {
  const { env, calls } = setup(() => fileResponse(bytes(10)));
  const res = await handleTiles(new Request(`${ORIGIN}/tiles/tiles-20261001/E005_N45.gaz`), env);
  assert.equal(calls[0].url, `${RELEASES}/tiles-20261001/E005_N45.gaz`);
  assert.equal(res.headers.get('Content-Type'), 'application/octet-stream');
});

test('an edge cache hit is served without calling fetch', async () => {
  const body = bytes(100);
  const { env, calls, cache } = setup(() => {
    throw new Error('fetch must not be called');
  });
  const url = `${ORIGIN}/tiles/tiles-20261001/W20_N30.rd5`;
  cache.store.set(
    url,
    new Response(body, { headers: { 'Cache-Control': 'public, max-age=31536000, immutable' } }),
  );
  const res = await handleTiles(new Request(url), env);
  assert.equal(res.status, 200);
  assert.equal(calls.length, 0);
  assert.deepEqual(new Uint8Array(await res.arrayBuffer()), body);

  const head = await handleTiles(new Request(url, { method: 'HEAD' }), env);
  assert.equal(head.status, 200);
  assert.equal(head.body, null);
  assert.equal(calls.length, 0);
});

test('HEAD goes upstream as HEAD, has no body and is not cached', async () => {
  const { env, calls, cache, settle } = setup(
    () => new Response(null, { status: 200, headers: { 'Content-Length': '1234' } }),
  );
  const url = `${ORIGIN}/tiles/tiles-20261001/W20_N30.rd5`;
  const res = await handleTiles(new Request(url, { method: 'HEAD' }), env);
  await settle();
  assert.equal(res.status, 200);
  assert.equal(calls[0].init.method, 'HEAD');
  assert.equal(res.headers.get('Content-Length'), '1234');
  assert.equal(res.body, null);
  assert.equal(cache.store.size, 0);
});

test('a Range request passes through as 206 and bypasses the cache', async () => {
  const { env, calls, cache, settle } = setup(
    () =>
      new Response(bytes(10), {
        status: 206,
        headers: { 'Content-Length': '10', 'Content-Range': 'bytes 0-9/4096' },
      }),
  );
  const url = `${ORIGIN}/tiles/tiles-20261001/W20_N30.rd5`;
  cache.store.set(url, new Response('cached whole file'));
  const res = await handleTiles(new Request(url, { headers: { Range: 'bytes=0-9' } }), env);
  await settle();
  assert.equal(res.status, 206);
  assert.equal(calls.length, 1, 'the cached copy is not used for a range');
  assert.equal(calls[0].init.headers.get('Range'), 'bytes=0-9');
  assert.equal(calls[0].init.redirect, 'follow');
  assert.equal(res.headers.get('Content-Range'), 'bytes 0-9/4096');
  assert.equal(res.headers.get('Content-Length'), '10');
  assert.equal((await res.arrayBuffer()).byteLength, 10);
  assert.equal(cache.store.size, 1);
  assert.equal(await cache.store.get(url).clone().text(), 'cached whole file');
});

test('upstream 404 is a 404, other failures are a 502, nothing cached', async () => {
  for (const [upstream, expected] of [
    [404, 404],
    [500, 502],
    [403, 502],
    [206, 502], // a partial answer to a request without Range
  ]) {
    const { env, cache, settle } = setup(() => new Response('x', { status: upstream }));
    const res = await handleTiles(
      new Request(`${ORIGIN}/tiles/tiles-20261001/W20_N30.rd5`),
      env,
    );
    await settle();
    assert.equal(res.status, expected, `upstream ${upstream}`);
    assert.equal(cache.store.size, 0);
  }
});

test('a fetch that throws is a 502', async () => {
  const { env } = setup(() => {
    throw new TypeError('network down');
  });
  const res = await handleTiles(new Request(`${ORIGIN}/tiles/tiles-20261001/W20_N30.rd5`), env);
  assert.equal(res.status, 502);
});

test('bad paths are a 404 and never reach the origin', async () => {
  const { env, calls } = setup(() => {
    throw new Error('fetch must not be called');
  });
  for (const path of [
    '/tiles/../x',
    '/tiles/tiles-20261001/../../etc',
    '/tiles/tiles-20261001%2FW20_N30.rd5',
    '/tiles/tiles-20261001/W20_N30%2Erd5',
    '/tiles/foo/W20_N30.rd5',
    '/tiles/tiles-20261001/evil.js',
    '/tiles/tiles-20261001/',
    '/tiles/',
  ]) {
    const res = await handleTiles(new Request(`${ORIGIN}${path}`), env);
    assert.equal(res.status, 404, path);
  }
  assert.equal(calls.length, 0);
});

test('POST is a 405, OPTIONS a 204', async () => {
  const { env, calls } = setup(() => {
    throw new Error('fetch must not be called');
  });
  const url = `${ORIGIN}/tiles/tiles-20261001/W20_N30.rd5`;
  for (const method of ['POST', 'PUT', 'DELETE']) {
    const res = await handleTiles(new Request(url, { method, body: method === 'DELETE' ? null : 'x' }), env);
    assert.equal(res.status, 405, method);
    assert.equal(res.headers.get('Allow'), 'GET, HEAD, OPTIONS');
  }
  const options = await handleTiles(new Request(url, { method: 'OPTIONS' }), env);
  assert.equal(options.status, 204);
  assert.equal(options.headers.get('Access-Control-Allow-Origin'), null);
  assert.equal(calls.length, 0);
});

test('cookies and authorization are not forwarded', async () => {
  const { env, calls } = setup(() => fileResponse(bytes(4)));
  await handleTiles(
    new Request(`${ORIGIN}/tiles/tiles-20261001/W20_N30.rd5`, {
      headers: {
        Cookie: 'session=secret',
        Authorization: 'Bearer secret',
        'X-Forwarded-For': '203.0.113.7',
        Range: 'bytes=0-3',
      },
    }),
    env,
  );
  const sent = calls[0].init.headers;
  assert.equal(sent.get('Cookie'), null);
  assert.equal(sent.get('Authorization'), null);
  assert.equal(sent.get('X-Forwarded-For'), null);
  assert.deepEqual([...sent.keys()], ['range']);

  const pointer = setup(() => new Response(JSON.stringify(POINTER)));
  await handleTiles(
    new Request(`${ORIGIN}/tiles/latest.json`, { headers: { Cookie: 'a=b', Authorization: 'x' } }),
    pointer.env,
  );
  assert.equal(pointer.calls[0].init.headers, undefined);
});
