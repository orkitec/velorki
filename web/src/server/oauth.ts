// SPDX-License-Identifier: AGPL-3.0-only
import { z } from 'zod';
import { type Config } from '@/config';
import { ApiError } from './errors';

/**
 * OAuth token relay.
 *
 * The whole reason this service exists: the client secrets of Strava and
 * Ride with GPS must not ship inside an open-source mobile app. The app does
 * the browser part of the OAuth dance and posts the resulting `code` here; we
 * add the secret, call the provider and hand back its answer untouched, so the
 * app keeps owning the tokens and we never store them.
 */

export const STRAVA_TOKEN_URL = 'https://www.strava.com/oauth/token';
export const RWGPS_TOKEN_URL = 'https://ridewithgps.com/oauth/token.json';
const UPSTREAM_TIMEOUT_MS = 10_000;

export const codeBodySchema = z.object({
  code: z.string().min(1).max(512),
  redirect_uri: z.string().min(1).max(2048),
});

export const refreshBodySchema = z.object({
  refresh_token: z.string().min(1).max(2048),
});

/** Run a zod schema over an unknown body and turn failures into invalid_request. */
export function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const result = schema.safeParse(body);
  if (!result.success) {
    const detail = result.error.issues
      .map((i) => `${i.path.join('.') || '(body)'}: ${i.message}`)
      .join('; ');
    throw new ApiError('invalid_request', detail);
  }
  return result.data;
}

/**
 * The redirect_uri is forwarded to the provider and therefore decides where a
 * stolen code could be sent. Only exact matches from the allowlist are
 * accepted - no prefix or wildcard matching.
 */
export function assertAllowedRedirect(config: Config, redirectUri: string): void {
  if (!config.OAUTH_REDIRECT_ALLOWLIST.includes(redirectUri)) {
    throw new ApiError('invalid_request', 'redirect_uri is not allowed.');
  }
}

/** Remove anything secret-looking from an upstream message before it is echoed. */
export function scrub(text: string, config: Config): string {
  let out = text;
  for (const secret of [config.STRAVA_CLIENT_SECRET, config.RWGPS_CLIENT_SECRET]) {
    if (secret !== undefined && secret.length > 0) out = out.split(secret).join('[redacted]');
  }
  return out.slice(0, 500);
}

interface UpstreamResult {
  status: number;
  body: unknown;
  text: string;
}

async function postForm(url: string, form: URLSearchParams): Promise<UpstreamResult> {
  let res: Response;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/x-www-form-urlencoded',
        accept: 'application/json',
      },
      body: form.toString(),
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  } catch {
    throw new ApiError('upstream_error', 'Could not reach the provider.');
  }

  const text = await res.text();
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    body = undefined;
  }
  return { status: res.status, body, text };
}

/** Best-effort human-readable error out of whatever the provider returned. */
function upstreamMessage(result: UpstreamResult): string {
  const body = result.body as { message?: unknown; error?: unknown; error_description?: unknown };
  for (const candidate of [body?.error_description, body?.message, body?.error]) {
    if (typeof candidate === 'string' && candidate.trim() !== '') return candidate.trim();
  }
  return result.text.trim() === '' ? `Provider responded with ${String(result.status)}.` : result.text;
}

/** Shared tail of every token exchange: call the provider, pass the answer on. */
export async function relay(
  config: Config,
  url: string,
  form: URLSearchParams,
): Promise<{ status: number; body: unknown }> {
  const result = await postForm(url, form);
  if (result.status < 200 || result.status >= 300) {
    // Never leak the client secret, even if the provider echoed it back.
    throw new ApiError('upstream_error', scrub(upstreamMessage(result), config));
  }
  if (result.body === undefined) {
    throw new ApiError('upstream_error', 'Provider returned a non-JSON response.');
  }
  return { status: result.status, body: result.body };
}
