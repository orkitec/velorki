// SPDX-License-Identifier: AGPL-3.0-only
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { ApiError } from './errors';

/**
 * Token wrapping.
 *
 * The phone never holds a Strava or Ride with GPS token in clear. The relay
 * encrypts every token it obtains for the phone under a key only the relay
 * has, the phone stores that wrapped form and sends it back with every
 * pass-through call, and the relay unwraps it in memory for the one upstream
 * request. Nothing is stored here, and a wrapped token is useless to anyone
 * who reads it off the phone: it only works through this relay, which checks
 * the subscription first.
 *
 * Wire form: `v1.<kid>.<nonce>.<ciphertext>`, base64url without padding, the
 * ciphertext carrying the GCM tag at its end. The additional data binds the
 * ciphertext to the service and the token kind, so a Strava wrap cannot be
 * replayed as a Ride with GPS one and a refresh token cannot be presented as
 * an access token.
 *
 * Keys come from `TOKEN_WRAP_KEYS`, `kid:base64key` entries separated by
 * commas. The first entry wraps; every entry unwraps, which is how a key is
 * rotated: add the new key in front, keep the old one until every phone has
 * been re-wrapped by a pass-through call, then drop it.
 */

export type WrappedService = 'strava' | 'rwgps';
export type TokenKind = 'access' | 'refresh';

export interface WrapKeys {
  /** The kid that wraps from now on. */
  readonly current: string;
  /** Every key that still unwraps, the current one included. */
  readonly keys: ReadonlyMap<string, Buffer>;
}

export interface Unwrapped {
  token: string;
  /** True when an older key unwrapped it, so the caller should re-wrap. */
  stale: boolean;
}

/** The header a pass-through call carries its wrapped access token in. */
export const TOKEN_HEADER = 'x-velorki-token';
/** Set on a pass-through answer when the token arrived under an old key. */
export const REWRAPPED_HEADER = 'x-velorki-token-rewrapped';

const VERSION = 'v1';
const KID_RE = /^[A-Za-z0-9_-]{1,32}$/;
const KEY_BYTES = 32;
const NONCE_BYTES = 12;
const TAG_BYTES = 16;
const MAX_TOKEN_BYTES = 4096;

/**
 * Parse `TOKEN_WRAP_KEYS`. Throws a plain Error naming the kid, never the key
 * material, because the message ends up in the startup log.
 */
export function parseWrapKeys(raw: string): WrapKeys {
  const entries = raw
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s !== '');
  if (entries.length === 0) throw new Error('TOKEN_WRAP_KEYS has no entries');
  const keys = new Map<string, Buffer>();
  let current: string | undefined;
  for (const entry of entries) {
    const colon = entry.indexOf(':');
    const kid = colon === -1 ? '' : entry.slice(0, colon);
    if (!KID_RE.test(kid)) {
      throw new Error('TOKEN_WRAP_KEYS entries are kid:base64key, with a kid of [A-Za-z0-9_-]{1,32}');
    }
    if (keys.has(kid)) throw new Error(`TOKEN_WRAP_KEYS names the kid "${kid}" twice`);
    const key = Buffer.from(entry.slice(colon + 1), 'base64');
    if (key.length !== KEY_BYTES) {
      throw new Error(`TOKEN_WRAP_KEYS key "${kid}" is not 32 bytes of base64`);
    }
    keys.set(kid, key);
    current ??= kid;
  }
  return { current: current ?? '', keys };
}

function aad(service: WrappedService, kind: TokenKind): Buffer {
  return Buffer.from(`${service}/${kind}`, 'utf8');
}

/** Encrypt `token` under the current key. */
export function wrapToken(
  keys: WrapKeys,
  service: WrappedService,
  kind: TokenKind,
  token: string,
): string {
  const key = keys.keys.get(keys.current);
  if (key === undefined) throw new Error('TOKEN_WRAP_KEYS has no current key');
  const nonce = randomBytes(NONCE_BYTES);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(aad(service, kind));
  const body = Buffer.concat([cipher.update(token, 'utf8'), cipher.final(), cipher.getAuthTag()]);
  return [VERSION, keys.current, nonce.toString('base64url'), body.toString('base64url')].join('.');
}

const NOT_VALID = 'The service token is not valid; connect the service again.';

/**
 * Decrypt a wrapped token. Every failure is the same 400: a client that sends
 * a malformed, foreign or tampered token has nothing to fix but reconnecting.
 */
export function unwrapToken(
  keys: WrapKeys,
  service: WrappedService,
  kind: TokenKind,
  wrapped: string,
): Unwrapped {
  if (wrapped.length > MAX_TOKEN_BYTES * 2) throw new ApiError('invalid_request', NOT_VALID);
  const parts = wrapped.split('.');
  if (parts.length !== 4 || parts[0] !== VERSION) throw new ApiError('invalid_request', NOT_VALID);
  const [, kid, nonceText, bodyText] = parts as [string, string, string, string];
  const key = keys.keys.get(kid);
  if (key === undefined) throw new ApiError('invalid_request', NOT_VALID);
  const nonce = Buffer.from(nonceText, 'base64url');
  const body = Buffer.from(bodyText, 'base64url');
  if (nonce.length !== NONCE_BYTES || body.length < TAG_BYTES) {
    throw new ApiError('invalid_request', NOT_VALID);
  }
  const decipher = createDecipheriv('aes-256-gcm', key, nonce);
  decipher.setAAD(aad(service, kind));
  decipher.setAuthTag(body.subarray(body.length - TAG_BYTES));
  let token: string;
  try {
    token = Buffer.concat([
      decipher.update(body.subarray(0, body.length - TAG_BYTES)),
      decipher.final(),
    ]).toString('utf8');
  } catch {
    throw new ApiError('invalid_request', NOT_VALID);
  }
  return { token, stale: kid !== keys.current };
}

/**
 * The provider's token JSON with `access_token` and `refresh_token` replaced
 * by their wrapped forms. Everything else, the athlete object included, is
 * handed on as it came.
 */
export function wrapTokensIn(body: unknown, keys: WrapKeys, service: WrappedService): unknown {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) return body;
  const out: Record<string, unknown> = { ...(body as Record<string, unknown>) };
  const access = out['access_token'];
  if (typeof access === 'string' && access !== '') {
    out['access_token'] = wrapToken(keys, service, 'access', access);
  }
  const refresh = out['refresh_token'];
  if (typeof refresh === 'string' && refresh !== '') {
    out['refresh_token'] = wrapToken(keys, service, 'refresh', refresh);
  }
  return out;
}

/** The 503 every token route answers while no wrapping key is configured. */
export function requireWrapKeys(keys: WrapKeys | undefined): WrapKeys {
  if (keys === undefined) {
    throw new ApiError('unavailable', 'Token wrapping is not configured on this server.');
  }
  return keys;
}
