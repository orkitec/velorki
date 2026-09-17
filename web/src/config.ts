// SPDX-License-Identifier: AGPL-3.0-only
import { z } from 'zod';

/**
 * All configuration comes from the environment (Orkify injects it into the
 * process). Every integration is optional: when its variables are missing the
 * corresponding routes degrade to 503 `unavailable` instead of the service
 * refusing to boot. Only genuinely malformed values (a bad URL, a non-numeric
 * price) are fatal.
 *
 * This is the relay's `api/src/config.ts` minus PORT/HOST (Next owns the
 * listener) plus the keys the two-host deployment needs.
 */

const bool01 = z
  .string()
  .optional()
  .transform((v) => v === '1' || v?.toLowerCase() === 'true');

/** Optional string that treats "" the same as unset. */
const optionalStr = z
  .string()
  .optional()
  .transform((v) => (v === undefined || v.trim() === '' ? undefined : v.trim()));

const optionalUrl = optionalStr.refine(
  (v) => v === undefined || /^https?:\/\//.test(v),
  { message: 'must be an http(s) URL' },
);

const numberWithDefault = (fallback: number) =>
  z
    .string()
    .optional()
    .transform((v) => (v === undefined || v.trim() === '' ? fallback : Number(v)))
    .refine((v) => Number.isFinite(v), { message: 'must be a number' });

/** Host names are compared case-insensitively and without a port. */
const hostWithDefault = (fallback: string) =>
  optionalStr.transform((v) => (v ?? fallback).toLowerCase().replace(/:\d+$/, ''));

const envSchema = z
  .object({
    LOG_LEVEL: z
      .enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'])
      .optional()
      .transform((v) => v ?? 'info'),
    APP_VERSION: optionalStr.transform((v) => v ?? 'dev'),
    PUBLIC_BASE_URL: optionalStr.transform((v) =>
      (v ?? 'https://velorki.com').replace(/\/+$/, ''),
    ),
    TRUST_PROXY: bool01,

    /* --------------------------------------------------------------- hosts */

    API_HOST: hostWithDefault('api.velorki.com'),
    SITE_HOST: hostWithDefault('velorki.com'),
    /** `1` also accepts api.localhost, `x-velorki-host: api` and `/__api/*`. */
    DEV_HOSTS: bool01,
    /**
     * Header carrying the real client IP (Cloudflare: `cf-connecting-ip`).
     * Only trustworthy when the origin is firewalled to the proxy.
     */
    CLIENT_IP_HEADER: optionalStr.transform((v) => v?.toLowerCase()),

    /* ------------------------------------------------------------ counters */

    COUNTERS: z.enum(['orkify', 'memory']).optional(),
    /** Set by Orkify; its presence is what makes `orkify` the counters default. */
    ORKIFY_EXEC_MODE: optionalStr,
    /** Set by Orkify per worker. Worker "0" owns the once-per-cluster chores. */
    ORKIFY_WORKER_ID: optionalStr,

    BROUTER_URL: optionalUrl.transform((v) => v?.replace(/\/+$/, '')),

    STRAVA_CLIENT_ID: optionalStr,
    STRAVA_CLIENT_SECRET: optionalStr,
    RWGPS_CLIENT_ID: optionalStr,
    RWGPS_CLIENT_SECRET: optionalStr,
    OAUTH_REDIRECT_ALLOWLIST: z
      .string()
      .optional()
      .transform((v) =>
        (v ?? '')
          .split(',')
          .map((s) => s.trim())
          .filter((s) => s !== ''),
      ),

    REVENUECAT_SECRET_KEY: optionalStr,
    REVENUECAT_ENTITLEMENT: optionalStr.transform((v) => v ?? 'plus'),
    REVENUECAT_MODE: z
      .enum(['live', 'stub'])
      .optional()
      .transform((v) => v ?? 'live'),

    LLM_BASE_URL: optionalUrl,
    LLM_API_KEY: optionalStr,
    LLM_MODEL: optionalStr,
    LLM_DAILY_BUDGET_USD: z
      .string()
      .optional()
      .transform((v) => (v === undefined || v.trim() === '' ? undefined : Number(v)))
      .refine((v) => v === undefined || (Number.isFinite(v) && v >= 0), {
        message: 'must be a non-negative number',
      }),
    LLM_USD_PER_1K_IN: numberWithDefault(0),
    LLM_USD_PER_1K_OUT: numberWithDefault(0),

    SHARE_DB_PATH: optionalStr.transform((v) => v ?? './data/share.sqlite'),

    /* -------------------------------------------------------- app linking */

    /** Apple Developer team id; without it no apple-app-site-association is served. */
    APPLE_TEAM_ID: optionalStr,
    /** Comma-separated SHA-256 signing fingerprints for assetlinks.json. */
    ANDROID_CERT_SHA256: z
      .string()
      .optional()
      .transform((v) =>
        (v ?? '')
          .split(',')
          .map((s) => s.trim())
          .filter((s) => s !== ''),
      ),
  })
  .transform((v) => ({
    ...v,
    // Orkify's cache only exists inside an orkify-managed process; everywhere
    // else (dev, tests, a plain `next start`) the memory backend is correct.
    COUNTERS: v.COUNTERS ?? (v.ORKIFY_EXEC_MODE === undefined ? 'memory' : 'orkify'),
  }))
  // A budget without prices costs nothing per request, so it never bites: the
  // spend stays 0 and the circuit breaker silently does nothing. Someone who
  // sets a budget means it, so this is fatal rather than a log line.
  .superRefine((v, ctx) => {
    if (v.LLM_DAILY_BUDGET_USD === undefined) return;
    if (v.LLM_USD_PER_1K_IN > 0 && v.LLM_USD_PER_1K_OUT > 0) return;
    ctx.addIssue({
      code: 'custom',
      path: ['LLM_DAILY_BUDGET_USD'],
      message:
        'needs LLM_USD_PER_1K_IN and LLM_USD_PER_1K_OUT to be greater than 0; with both at 0 the estimated spend stays 0 and the budget never applies',
    });
  });

export type Config = z.infer<typeof envSchema>;

/** The env map. Typed loosely so tests can pass a plain literal. */
export type EnvSource = Record<string, string | undefined>;

export function loadConfig(env: EnvSource = process.env): Config {
  const parsed = envSchema.safeParse(env);
  if (!parsed.success) {
    const details = parsed.error.issues
      .map((i) => `  ${i.path.join('.') || '(root)'}: ${i.message}`)
      .join('\n');
    throw new Error(`Invalid environment configuration:\n${details}`);
  }
  return parsed.data;
}

/** Strava token exchange is only possible with both client id and secret. */
export function stravaConfigured(c: Config): boolean {
  return Boolean(c.STRAVA_CLIENT_ID && c.STRAVA_CLIENT_SECRET);
}

export function rwgpsConfigured(c: Config): boolean {
  return Boolean(c.RWGPS_CLIENT_ID && c.RWGPS_CLIENT_SECRET);
}

/**
 * The API key is deliberately not required: self-hosted OpenAI-compatible
 * servers (llama.cpp, vLLM, Ollama) commonly accept any or no key.
 */
export function llmConfigured(c: Config): boolean {
  return Boolean(c.LLM_BASE_URL && c.LLM_MODEL);
}

/** The worker this process is, as Orkify numbers them. "0" owns the chores. */
export function workerId(c: Config): string {
  return c.ORKIFY_WORKER_ID ?? '0';
}

/**
 * The client IP used as a rate-limit key.
 *
 * Nothing in a request is believed unless `TRUST_PROXY` says a proxy we control
 * is in front: a client that can reach the origin directly would otherwise pick
 * its own rate-limit bucket per request, simply by sending the header.
 *
 * Behind such a proxy, `CLIENT_IP_HEADER` wins when configured (Cloudflare's
 * `CF-Connecting-IP`, which the edge overwrites and the origin firewall makes
 * unforgeable); otherwise the left-most `X-Forwarded-For` entry is the original
 * client as appended by the first proxy. Everything else shares the key
 * "unknown", which is a shared bucket, not an open door.
 */
export function clientIp(c: Config, headers: Headers): string {
  if (!c.TRUST_PROXY) return 'unknown';
  if (c.CLIENT_IP_HEADER !== undefined) {
    const direct = headers.get(c.CLIENT_IP_HEADER)?.trim();
    if (direct !== undefined && direct !== '') return direct;
  }
  const first = headers.get('x-forwarded-for')?.split(',')[0]?.trim();
  if (first !== undefined && first !== '') return first;
  return 'unknown';
}
