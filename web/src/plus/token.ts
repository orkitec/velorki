// SPDX-License-Identifier: AGPL-3.0-only
import { createHmac, timingSafeEqual } from 'node:crypto';

/**
 * The short-lived Plus token `POST /plus/web` hands a browser, sent back as
 * `Authorization: Bearer vpt1.<payload>.<mac>` to the Plus routes in place
 * of a RevenueCat app user id.
 *
 * The payload is `{"s": subject, "e": expiry in Unix seconds}`, base64url;
 * the mac is HMAC-SHA256 under `PLUS_TOKEN_SECRET` over `vpt1.<payload>`.
 * The subject is a keyed hash of the entitled RevenueCat id, never the id
 * itself: a RevenueCat id is a bearer credential of its own on this relay,
 * and the payload is readable by anyone holding the token. The subject is
 * the per-rider rate-limit key, so a browser's requests count against one
 * subscriber however often it signs in.
 */

export const PLUS_TOKEN_PREFIX = 'vpt1.';

/** How long a Plus token is good for. */
export const PLUS_TOKEN_TTL_S = 3_600;

function keyOf(secret: string): Buffer {
  return Buffer.from(secret, 'base64');
}

function mac(secret: string, data: string): Buffer {
  return createHmac('sha256', keyOf(secret)).update(data).digest();
}

/** The subject for `appUserId`: stable per id and secret, and not reversible. */
export function plusSubject(secret: string, appUserId: string): string {
  return mac(secret, `subject:${appUserId}`).subarray(0, 16).toString('base64url');
}

export function isPlusToken(bearer: string): boolean {
  return bearer.startsWith(PLUS_TOKEN_PREFIX);
}

export function mintPlusToken(
  secret: string,
  subject: string,
  nowMs: number = Date.now(),
): { token: string; expiresAt: number } {
  const expiresAt = Math.floor(nowMs / 1000) + PLUS_TOKEN_TTL_S;
  const payload = Buffer.from(JSON.stringify({ s: subject, e: expiresAt })).toString('base64url');
  const signed = `${PLUS_TOKEN_PREFIX}${payload}`;
  return { token: `${signed}.${mac(secret, signed).toString('base64url')}`, expiresAt };
}

/** The subject of a valid, unexpired token, or null. */
export function verifyPlusToken(
  secret: string,
  token: string,
  nowMs: number = Date.now(),
): string | null {
  if (!isPlusToken(token)) return null;
  const dot = token.lastIndexOf('.');
  if (dot <= PLUS_TOKEN_PREFIX.length) return null;
  const signed = token.slice(0, dot);
  const given = Buffer.from(token.slice(dot + 1), 'base64url');
  const expected = mac(secret, signed);
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
  let payload: unknown;
  try {
    payload = JSON.parse(
      Buffer.from(signed.slice(PLUS_TOKEN_PREFIX.length), 'base64url').toString('utf8'),
    );
  } catch {
    return null;
  }
  if (typeof payload !== 'object' || payload === null) return null;
  const { s, e } = payload as { s?: unknown; e?: unknown };
  if (typeof s !== 'string' || typeof e !== 'number') return null;
  if (e * 1000 <= nowMs) return null;
  return s;
}
