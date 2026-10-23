// SPDX-License-Identifier: AGPL-3.0-only
//
// node --test deploy/cloudflare/test/

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  handleUpload,
  parseUploadUrl,
  MAX_BODY_BYTES,
} from '../pages/cloudkit_upload.mjs';

const UPLOAD = 'https://cws.icloud-content.com/B/abc/singleFileUpload?tk=SECRET&x=1';
const RECEIPT = { singleFile: { size: 3, fileChecksum: 'abc', receipt: 'r' } };

function fakeFetch(respond) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    calls.push({ url, init });
    return respond(url, init);
  };
  return { fetch, calls };
}

const ok = () =>
  new Response(JSON.stringify(RECEIPT), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });

function post(url, body = new Uint8Array([1, 2, 3]), headers = {}) {
  return new Request(
    `https://app.velorki.com/cloudkit/upload?url=${encodeURIComponent(url)}`,
    { method: 'POST', body, headers: { 'Content-Type': 'application/gzip', ...headers } },
  );
}

test('parseUploadUrl accepts Apple upload hosts', () => {
  assert.ok(parseUploadUrl(UPLOAD));
  assert.ok(parseUploadUrl('https://p57-contentws.icloud.com/a/singleFileUpload?tk=t'));
  // CloudKit JS spells the default port out.
  assert.ok(parseUploadUrl('https://cws.icloud-content.com:443/a/singleFileUpload?tk=t'));
});

test('parseUploadUrl refuses anything else', () => {
  for (const bad of [
    null,
    '',
    'nonsense',
    'http://cws.icloud-content.com/a/singleFileUpload?tk=t',
    'https://evil.example/a/singleFileUpload?tk=t',
    'https://cws.icloud-content.com.evil.example/a/singleFileUpload?tk=t',
    'https://evilcws.icloud-content.com/a/singleFileUpload?tk=t',
    'https://cws.icloud-content.com:8443/a/singleFileUpload?tk=t',
    'https://u:p@cws.icloud-content.com/a/singleFileUpload?tk=t',
    'https://cws.icloud-content.com/a/other?tk=t',
    'https://cws.icloud-content.com/a/singleFileUpload',
    'https://cws.icloud-content.com/a/singleFileUpload?tk=t#x',
    'https://pX-contentws.icloud.com/a/singleFileUpload?tk=t',
    'https://p5-contentws.icloud.com.evil.example/a/singleFileUpload?tk=t',
  ]) {
    assert.equal(parseUploadUrl(bad), null, String(bad));
  }
});

test('only POST', async () => {
  const { fetch, calls } = fakeFetch(ok);
  const res = await handleUpload(
    new Request(`https://app.velorki.com/cloudkit/upload?url=${encodeURIComponent(UPLOAD)}`),
    { fetch },
  );
  assert.equal(res.status, 405);
  assert.equal(res.headers.get('Allow'), 'POST');
  assert.equal(calls.length, 0);
});

test('an invalid URL is a 400 and nothing is fetched', async () => {
  const { fetch, calls } = fakeFetch(ok);
  const res = await handleUpload(post('https://evil.example/singleFileUpload?tk=t'), { fetch });
  assert.equal(res.status, 400);
  assert.equal(calls.length, 0);
});

test('forwards the bytes with the content type only, returns the receipt', async () => {
  const { fetch, calls } = fakeFetch(ok);
  const res = await handleUpload(
    post(UPLOAD, new Uint8Array([9, 8, 7]), {
      Cookie: 'a=b',
      Authorization: 'Bearer x',
      'X-Other': '1',
    }),
    { fetch },
  );
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), RECEIPT);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, UPLOAD);
  assert.equal(calls[0].init.method, 'POST');
  assert.deepEqual(calls[0].init.headers, { 'Content-Type': 'application/gzip' });
  assert.deepEqual([...calls[0].init.body], [9, 8, 7]);
  assert.equal(calls[0].init.redirect, 'error');
});

test("Apple's error status passes through", async () => {
  const { fetch } = fakeFetch(
    () =>
      new Response('{"error":"expired"}', {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      }),
  );
  const res = await handleUpload(post(UPLOAD), { fetch });
  assert.equal(res.status, 401);
  assert.deepEqual(await res.json(), { error: 'expired' });
});

test('a body over the cap is a 413, by Content-Length or by count', async () => {
  const { fetch, calls } = fakeFetch(ok);
  const declared = await handleUpload(
    post(UPLOAD, new Uint8Array(1), { 'Content-Length': String(MAX_BODY_BYTES + 1) }),
    { fetch },
  );
  assert.equal(declared.status, 413);

  const chunk = new Uint8Array(1024 * 1024);
  let sent = 0;
  const stream = new ReadableStream({
    pull(controller) {
      if (sent++ > 20) controller.close();
      else controller.enqueue(chunk);
    },
  });
  const counted = await handleUpload(
    new Request(`https://app.velorki.com/cloudkit/upload?url=${encodeURIComponent(UPLOAD)}`, {
      method: 'POST',
      body: stream,
      duplex: 'half',
    }),
    { fetch },
  );
  assert.equal(counted.status, 413);
  assert.equal(calls.length, 0);
});

test('a non-JSON or oversized answer is not passed on', async () => {
  const html = fakeFetch(
    () => new Response('<html>', { status: 200, headers: { 'Content-Type': 'text/html' } }),
  );
  assert.equal((await handleUpload(post(UPLOAD), { fetch: html.fetch })).status, 502);

  const big = fakeFetch(
    () =>
      new Response('{"a":"' + 'x'.repeat(70_000) + '"}', {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
  );
  assert.equal((await handleUpload(post(UPLOAD), { fetch: big.fetch })).status, 502);
});

test('a failing fetch is a 502 that names no URL', async () => {
  const { fetch } = fakeFetch(() => {
    throw new Error('boom ' + UPLOAD);
  });
  const res = await handleUpload(post(UPLOAD), { fetch });
  assert.equal(res.status, 502);
  assert.ok(!(await res.text()).includes('SECRET'));
});
