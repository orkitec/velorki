// SPDX-License-Identifier: AGPL-3.0-only
//
// CloudKit's asset upload under the web app's own origin.
//
// CloudKit JS saves a record's `body` asset by POSTing the file to a
// one-time URL that api.apple-cloudkit.com hands out
// (https://cws.icloud-content.com/<id>/singleFileUpload?tk=...), and that
// host answers CORS for a short list of origins that does not include ours.
// The app's XMLHttpRequest wrapper (cloudkit_web_js.dart) therefore sends the same
// POST here:
//
//   POST /cloudkit/upload?url=<encoded upload URL>
//     -> the upload URL, body and Content-Type unchanged; Apple's status and
//        JSON answer (the file's receipt) come back.
//
// The URL must be https on cws.icloud-content.com or pNN-contentws.icloud.com,
// no port or credentials, a path ending in /singleFileUpload, with a `tk`.
// The body is read to the end, at most 16 MB (a library body is a few KB to
// a few MB), and sent on whole. Only Content-Type is forwarded: no cookies,
// no Authorization, nothing else of the request. Nothing is stored or
// cached, and nothing is logged: `tk` is a credential for fifteen minutes.
//
// No Cloudflare globals here: `env` carries fetch, so the Pages Function
// wires the real one and tests fake it.

export const MAX_BODY_BYTES = 16 * 1024 * 1024;
export const MAX_ANSWER_BYTES = 64 * 1024;
const TIMEOUT_MS = 30_000;
const HOST = /^(cws\.icloud-content\.com|p\d+-contentws\.icloud\.com)$/;
const PATH_END = '/singleFileUpload';

/** The upload URL when `raw` is one Apple hands out, else null. */
export function parseUploadUrl(raw) {
  if (typeof raw !== 'string' || raw === '') return null;
  let url;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== 'https:') return null;
  if (!HOST.test(url.hostname)) return null;
  if (url.port !== '' || url.username !== '' || url.password !== '') return null;
  if (url.hash !== '') return null;
  if (!url.pathname.endsWith(PATH_END)) return null;
  if (!url.searchParams.has('tk')) return null;
  return url;
}

function error(status, message, headers = {}) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...headers },
  });
}

/** The request body, whole, or null when it is over the cap. */
async function readCapped(request, cap) {
  const declared = request.headers.get('Content-Length');
  if (declared !== null && Number(declared) > cap) return null;
  if (request.body === null) return new Uint8Array(0);
  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > cap) {
      await reader.cancel().catch(() => undefined);
      return null;
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return out;
}

/**
 * The upstream answer's text when it is JSON within the cap, else null. Told
 * by parsing, not by Content-Type, which Apple does not promise.
 */
async function readAnswer(response) {
  const declared = response.headers.get('Content-Length');
  if (declared !== null && Number(declared) > MAX_ANSWER_BYTES) {
    await response.body?.cancel().catch(() => undefined);
    return null;
  }
  const reader = response.body?.getReader();
  if (reader === undefined) return null;
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_ANSWER_BYTES) {
      await reader.cancel().catch(() => undefined);
      return null;
    }
    chunks.push(value);
  }
  const text = new TextDecoder();
  const answer = chunks.map((c) => text.decode(c, { stream: true })).join('') + text.decode();
  try {
    JSON.parse(answer);
  } catch {
    return null;
  }
  return answer;
}

export async function handleUpload(request, env) {
  if (request.method !== 'POST') {
    return error(405, 'method not allowed', { Allow: 'POST' });
  }
  const target = parseUploadUrl(new URL(request.url).searchParams.get('url'));
  if (target === null) return error(400, 'not a CloudKit upload URL');

  const body = await readCapped(request, MAX_BODY_BYTES);
  if (body === null) return error(413, 'body too large');

  const headers = {};
  const type = request.headers.get('Content-Type');
  if (type !== null) headers['Content-Type'] = type;

  let upstream;
  try {
    upstream = await env.fetch(target.href, {
      method: 'POST',
      headers,
      body,
      redirect: 'error',
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch {
    return error(502, 'upload failed');
  }
  const answer = await readAnswer(upstream);
  if (answer === null) {
    return error(upstream.ok ? 502 : upstream.status, 'unexpected answer from CloudKit');
  }
  return new Response(answer, {
    status: upstream.status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}
