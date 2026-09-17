// SPDX-License-Identifier: AGPL-3.0-only
import { pino, type Logger } from 'pino';
import type { Config } from '@/config';
import { workerId } from '@/config';

export type { Logger };

/**
 * Credentials must never reach the log, not even at trace level. `authorization`
 * is redacted both as a header path and as a bare field, because handler-level
 * code logs plain objects rather than Fastify's req/res pair.
 */
const REDACT_PATHS = [
  'req.headers.authorization',
  'req.headers.cookie',
  'res.headers["set-cookie"]',
  'authorization',
];

export function createLogger(config: Config): Logger {
  return pino({
    level: config.LOG_LEVEL,
    // Replaces pino's pid/hostname: in a cluster the worker number is the only
    // part that tells two identical lines apart.
    base: { worker: workerId(config) },
    redact: { paths: REDACT_PATHS, censor: '[redacted]' },
  });
}

export const CLIENT_HEADER = 'x-velorki-client';

/** Per-request child logger: the request id, and the client when it sent one. */
export function requestLogger(base: Logger, headers: Headers, requestId: string): Logger {
  const raw = headers.get(CLIENT_HEADER)?.trim();
  const client = raw === undefined || raw === '' ? undefined : raw.slice(0, 128);
  return base.child(client === undefined ? { reqId: requestId } : { reqId: requestId, client });
}
