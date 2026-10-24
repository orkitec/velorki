// SPDX-License-Identifier: AGPL-3.0-only
//
// The store API clients prices-stores.mjs and prices-match-play.mjs share:
// signing in to App Store Connect (an ES256 JWT from the .p8 key) and to the
// Google Play Developer API (a service account's RS256 assertion traded for an
// OAuth token), fetching with a timeout, and turning a refusal into a
// StoreError that says what is wrong (for a 403, which permission is missing).
// Node built-ins only. Nothing here prints; no message carries a key, a token
// or a request body.
//
//   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8_BASE64   App Store Connect API key
//   PLAY_SERVICE_ACCOUNT_JSON                       Google Play service account

import { createPrivateKey, sign } from 'node:crypto';
import { APP_STORE_APP_ID, PLAY_PACKAGE, PRODUCTS, ascCurrentPrices, joinAsc } from './prices-lib.mjs';

const TIMEOUT_MS = 30_000;
const ASC_API = 'https://api.appstoreconnect.apple.com';
export const PLAY_API = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PLAY_PACKAGE}`;

export class StoreError extends Error {}

const base64url = (input) => Buffer.from(input).toString('base64url');

function jwt(header, payload, key, options) {
  const data = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const signature = sign('sha256', Buffer.from(data), { key, ...options });
  return `${data}.${signature.toString('base64url')}`;
}

/** The store's own explanation from an error body, never the request. */
async function errorDetail(response) {
  try {
    const body = await response.json();
    const asc = body?.errors?.[0];
    if (asc) return [asc.title, asc.detail].filter(Boolean).join(': ');
    if (body?.error?.message) return body.error.message;
    if (body?.error_description) return body.error_description;
    if (typeof body?.error === 'string') return body.error;
  } catch {
    // not JSON
  }
  return response.statusText;
}

/** fetch → parsed JSON, or a StoreError; `forbidden` explains a 403. */
export async function getJson(url, init, forbidden) {
  let response;
  try {
    response = await fetch(url, { ...init, signal: AbortSignal.timeout(TIMEOUT_MS) });
  } catch (error) {
    throw new StoreError(`network error (${error instanceof Error ? error.message : String(error)})`);
  }
  if (response.ok) return response.json();
  const detail = await errorDetail(response);
  const path = new URL(url).pathname;
  if (response.status === 401) throw new StoreError(`401 on ${path}: the credentials were refused (${detail})`);
  if (response.status === 403) throw new StoreError(`403 on ${path}: ${forbidden} (${detail})`);
  throw new StoreError(`HTTP ${response.status} on ${path} (${detail})`);
}

// ---------------------------------------------------------------------------
// App Store Connect

const ASC_FORBIDDEN =
  'the App Store Connect API key may not read subscriptions; it needs the App Manager role ' +
  '(or Admin) under Users and Access → Integrations → App Store Connect API';

/** The ASC_* variables that are not set. */
export function missingAscEnv(env = process.env) {
  return ['ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_KEY_P8_BASE64'].filter((name) => !env[name]);
}

/**
 * The current App Store price of both Plus subscriptions per territory, in
 * prices.json's shape: { <CC>: { currency, monthly, yearly } }.
 */
export async function appStorePrices() {
  const missing = missingAscEnv();
  if (missing.length > 0) throw new StoreError(`missing ${missing.join(', ')}`);
  const { ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8_BASE64 } = process.env;

  let key;
  try {
    key = createPrivateKey(Buffer.from(ASC_KEY_P8_BASE64, 'base64').toString('utf8'));
  } catch {
    throw new StoreError('ASC_KEY_P8_BASE64 is not a base64-encoded .p8 private key');
  }
  const now = Math.floor(Date.now() / 1000);
  // ES256 with the raw r||s signature JWTs use; App Store Connect takes at most 20 minutes.
  const token = jwt(
    { alg: 'ES256', kid: ASC_KEY_ID, typ: 'JWT' },
    { iss: ASC_ISSUER_ID, iat: now, exp: now + 15 * 60, aud: 'appstoreconnect-v1' },
    key,
    { dsaEncoding: 'ieee-p1363' },
  );
  const get = (url) =>
    getJson(url.startsWith('http') ? url : `${ASC_API}${url}`, { headers: { authorization: `Bearer ${token}` } }, ASC_FORBIDDEN);

  const groups = await get(
    `/v1/apps/${APP_STORE_APP_ID}/subscriptionGroups?include=subscriptions&limit=50&limit[subscriptions]=50`,
  );
  const subscriptions = new Map(
    (groups.included ?? [])
      .filter((item) => item.type === 'subscriptions')
      .map((item) => [item.attributes?.productId, item.id]),
  );

  const today = new Date().toISOString().slice(0, 10);
  const current = {};
  for (const [period, { productId }] of Object.entries(PRODUCTS)) {
    const id = subscriptions.get(productId);
    if (!id) throw new StoreError(`no subscription with product id ${productId} in app ${APP_STORE_APP_ID}`);
    const pages = [];
    let next =
      `/v1/subscriptions/${id}/prices?include=subscriptionPricePoint,territory` +
      '&fields[subscriptionPricePoints]=customerPrice&fields[territories]=currency&limit=200';
    while (next) {
      const page = await get(next);
      pages.push(page);
      next = page.links?.next ?? null;
    }
    current[period] = ascCurrentPrices(pages, today);
  }
  return joinAsc(current.monthly, current.yearly);
}

// ---------------------------------------------------------------------------
// Google Play

export const PLAY_FORBIDDEN =
  'the service account may not read this app\'s subscriptions; in Play Console → Users and ' +
  'permissions it needs, for this app, "View app information (read-only)" and "View financial ' +
  'data" (or "Manage store presence"), and the Google Play Android Developer API enabled in its ' +
  'Cloud project';

/**
 * Signs in with PLAY_SERVICE_ACCOUNT_JSON → `call(method, path, body,
 * forbidden)` against this app under PLAY_API (`path` starts with "/").
 */
export async function playSession() {
  const raw = process.env.PLAY_SERVICE_ACCOUNT_JSON;
  if (!raw) throw new StoreError('missing PLAY_SERVICE_ACCOUNT_JSON');
  let account;
  try {
    account = JSON.parse(raw);
  } catch {
    throw new StoreError('PLAY_SERVICE_ACCOUNT_JSON is not JSON');
  }
  if (!account.client_email || !account.private_key) {
    throw new StoreError('PLAY_SERVICE_ACCOUNT_JSON has no client_email or private_key');
  }
  const tokenUri = account.token_uri ?? 'https://oauth2.googleapis.com/token';
  const now = Math.floor(Date.now() / 1000);
  let assertion;
  try {
    assertion = jwt(
      { alg: 'RS256', typ: 'JWT' },
      {
        iss: account.client_email,
        scope: 'https://www.googleapis.com/auth/androidpublisher',
        aud: tokenUri,
        iat: now,
        exp: now + 3600,
      },
      createPrivateKey(account.private_key),
    );
  } catch {
    throw new StoreError('the private_key in PLAY_SERVICE_ACCOUNT_JSON could not be read');
  }
  const grant = await getJson(
    tokenUri,
    {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
    },
    'the service account may not get a token',
  );
  const authorization = `Bearer ${grant.access_token}`;
  return (method, path, body, forbidden = PLAY_FORBIDDEN) =>
    getJson(
      `${PLAY_API}${path}`,
      body === undefined
        ? { method, headers: { authorization } }
        : { method, headers: { authorization, 'content-type': 'application/json' }, body: JSON.stringify(body) },
      forbidden,
    );
}
