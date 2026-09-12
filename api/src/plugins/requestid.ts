// SPDX-License-Identifier: AGPL-3.0-only
import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';

export const REQUEST_ID_HEADER = 'x-request-id';
export const CLIENT_HEADER = 'x-velorki-client';

/**
 * Node gives a repeated header as an array; take the first value and keep the
 * result typed as `string | undefined` rather than letting `any` spread.
 */
export function firstHeaderValue(raw: unknown): string | undefined {
  if (typeof raw === 'string') return raw;
  if (Array.isArray(raw)) {
    const first = (raw as unknown[])[0];
    return typeof first === 'string' ? first : undefined;
  }
  return undefined;
}

/** Reuse a caller-supplied X-Request-Id when it looks sane, otherwise mint one. */
export function requestIdFrom(req: { headers: Record<string, unknown> }): string {
  const value = firstHeaderValue(req.headers[REQUEST_ID_HEADER]);
  if (value !== undefined) {
    const trimmed = value.trim();
    // Bound the length and charset: the id goes straight back out in a header
    // and into the logs, so untrusted input must not be able to inject either.
    if (trimmed.length > 0 && trimmed.length <= 128 && /^[\w.:@/+-]+$/.test(trimmed)) {
      return trimmed;
    }
  }
  return randomUUID();
}

function headerString(req: FastifyRequest, name: string): string | undefined {
  const value = firstHeaderValue(req.headers[name]);
  if (value === undefined) return undefined;
  const trimmed = value.trim();
  return trimmed === '' ? undefined : trimmed.slice(0, 128);
}

/**
 * Echoes X-Request-Id on every response and attaches the client identifier
 * (e.g. "android/1.0.0+1") to the per-request logger when the header is
 * present. Registered directly on the root instance (not via `register`) so
 * the hook is not encapsulated into a child scope.
 */
export function registerRequestId(app: FastifyInstance): void {
  app.addHook('onRequest', async (req, reply) => {
    reply.header(REQUEST_ID_HEADER, req.id);
    const client = headerString(req, CLIENT_HEADER);
    if (client !== undefined) {
      // Rebinding req.log adds the field to every later log line of this request.
      req.log = req.log.child({ client });
    }
  });
}
