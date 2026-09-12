// SPDX-License-Identifier: AGPL-3.0-only
import { z } from 'zod';

/**
 * All configuration comes from the environment (Orkify injects it into the
 * process). Every integration is optional: when its variables are missing the
 * corresponding routes degrade to 503 `unavailable` instead of the service
 * refusing to boot. Only genuinely malformed values (a non-numeric PORT, a
 * bad URL) are fatal.
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

const envSchema = z.object({
  PORT: numberWithDefault(8080),
  HOST: optionalStr.transform((v) => v ?? '0.0.0.0'),
  LOG_LEVEL: z
    .enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'])
    .optional()
    .transform((v) => v ?? 'info'),
  APP_VERSION: optionalStr.transform((v) => v ?? 'dev'),
  PUBLIC_BASE_URL: optionalStr.transform((v) => (v ?? 'http://localhost:8080').replace(/\/+$/, '')),
  TRUST_PROXY: bool01,

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
});

export type Config = z.infer<typeof envSchema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
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
