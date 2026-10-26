// SPDX-License-Identifier: AGPL-3.0-only
// node --test app/web_test/
// The response headers web/_headers gives every page (Cloudflare Pages, and
// tool/web_serve.py locally).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const file = readFileSync(new URL('../web/_headers', import.meta.url), 'utf8');

/** The headers of the rule for `pattern`, by lower-case name. */
function rule(pattern) {
  const headers = {};
  let current = null;
  for (const line of file.split('\n')) {
    if (!line.trim() || line.trimStart().startsWith('#')) continue;
    if (!/^\s/.test(line)) {
      current = line.trim();
      continue;
    }
    if (current !== pattern) continue;
    const at = line.indexOf(':');
    headers[line.slice(0, at).trim().toLowerCase()] = line.slice(at + 1).trim();
  }
  return headers;
}

const all = rule('/*');
const csp = Object.fromEntries(
  all['content-security-policy']
    .split(';')
    .map((d) => d.trim().split(/\s+/))
    .filter((d) => d[0])
    .map(([name, ...sources]) => [name, sources]),
);

test('the sign-in popups keep their opener, and Chrome still isolates the page', () => {
  // COOP same-origin would cut the Google and Apple popups off from the page
  // they answer to; Document-Isolation-Policy isolates without it.
  assert.equal(all['cross-origin-opener-policy'], 'same-origin-allow-popups');
  assert.equal(all['document-isolation-policy'], 'isolate-and-credentialless');
  // COEP without COOP same-origin isolates nothing and only restricts frames.
  assert.equal(all['cross-origin-embedder-policy'], undefined);
});

test('scripts come from the site, Google Identity Services and CloudKit JS only', () => {
  assert.deepEqual(csp['script-src'], [
    "'self'",
    "'wasm-unsafe-eval'",
    'https://accounts.google.com/gsi/client',
    'https://cdn.apple-cloudkit.com',
  ]);
  assert.deepEqual(csp['frame-src'], ['https://accounts.google.com/gsi/']);
  assert.ok(csp['style-src'].includes('https://accounts.google.com/gsi/style'));
});

test("a place's details come from the OpenStreetMap API", () => {
  assert.ok(csp['connect-src'].includes('https://api.openstreetmap.org'));
});

test('sync talks to Google Drive, CloudKit and their sign-in services', () => {
  for (const host of [
    'https://accounts.google.com/gsi/',
    'https://www.googleapis.com',
    'https://api.apple-cloudkit.com',
    'https://*.icloud-content.com',
    'https://*.icloud.com',
  ]) {
    assert.ok(csp['connect-src'].includes(host), host);
  }
  // Nothing beyond what sync needs: no other Google or Apple host.
  const sync = csp['connect-src'].filter((h) => /google|apple|icloud/.test(h));
  assert.equal(sync.length, 5);
});

test('the page cannot be framed, post forms or load plugins', () => {
  assert.deepEqual(csp['frame-ancestors'], ["'none'"]);
  assert.deepEqual(csp['form-action'], ["'none'"]);
  assert.deepEqual(csp['object-src'], ["'none'"]);
});

test('the planner is kept out of search indexes; velorki.com is the page to show', () => {
  assert.equal(all['x-robots-tag'], 'noindex');
});
