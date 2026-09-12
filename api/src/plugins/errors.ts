// SPDX-License-Identifier: AGPL-3.0-only
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';

/** The complete set of error codes in the public API contract. */
export type ErrorCode =
  | 'invalid_request'
  | 'not_entitled'
  | 'consent_required'
  | 'not_found'
  | 'rate_limited'
  | 'upstream_error'
  | 'unavailable';

export const ERROR_STATUS: Record<ErrorCode, number> = {
  invalid_request: 400,
  not_entitled: 401,
  consent_required: 403,
  not_found: 404,
  rate_limited: 429,
  upstream_error: 502,
  unavailable: 503,
};

export interface ErrorBody {
  error: {
    code: ErrorCode;
    message: string;
    retry_after_s?: number;
  };
}

/** Every failure path in the service throws (or replies with) one of these. */
export class ApiError extends Error {
  readonly code: ErrorCode;
  readonly statusOverride?: number;
  readonly retryAfterS?: number;

  constructor(
    code: ErrorCode,
    message: string,
    opts: { retryAfterS?: number; status?: number } = {},
  ) {
    super(message);
    this.name = 'ApiError';
    this.code = code;
    if (opts.retryAfterS !== undefined) this.retryAfterS = opts.retryAfterS;
    if (opts.status !== undefined) this.statusOverride = opts.status;
  }

  get status(): number {
    return this.statusOverride ?? ERROR_STATUS[this.code];
  }

  toBody(): ErrorBody {
    const body: ErrorBody = { error: { code: this.code, message: this.message } };
    if (this.retryAfterS !== undefined) body.error.retry_after_s = this.retryAfterS;
    return body;
  }
}

export function errorBody(code: ErrorCode, message: string, retryAfterS?: number): ErrorBody {
  return new ApiError(code, message, retryAfterS === undefined ? {} : { retryAfterS }).toBody();
}

/** Send an ApiError on a normal (non-SSE) reply, including Retry-After. */
export function sendError(reply: FastifyReply, err: ApiError): FastifyReply {
  if (err.retryAfterS !== undefined) reply.header('retry-after', String(err.retryAfterS));
  return reply.code(err.status).type('application/json; charset=utf-8').send(err.toBody());
}

/**
 * Map anything thrown inside a handler onto the uniform error body. Fastify's
 * own validation / body-limit errors are translated rather than leaking their
 * default shape.
 */
export function toApiError(err: unknown): ApiError {
  if (err instanceof ApiError) return err;

  const e = err as { code?: string; statusCode?: number; message?: string } | undefined;
  const fastifyCode = e?.code ?? '';

  if (fastifyCode === 'FST_ERR_CTP_BODY_TOO_LARGE') {
    return new ApiError('invalid_request', 'Request body is too large.');
  }
  if (fastifyCode === 'FST_ERR_CTP_EMPTY_JSON_BODY' || fastifyCode === 'FST_ERR_CTP_INVALID_MEDIA_TYPE') {
    return new ApiError('invalid_request', 'A JSON request body is required.');
  }
  if (fastifyCode.startsWith('FST_ERR_VALIDATION') || e?.statusCode === 400) {
    return new ApiError('invalid_request', e?.message ?? 'Invalid request.');
  }
  if (e?.statusCode === 404) {
    return new ApiError('not_found', 'Not found.');
  }
  if (fastifyCode === 'FST_ERR_CTP_INVALID_JSON_BODY' || err instanceof SyntaxError) {
    return new ApiError('invalid_request', 'Request body is not valid JSON.');
  }
  return new ApiError('upstream_error', 'Internal server error.', { status: 500 });
}

export function registerErrorHandler(app: FastifyInstance): void {
  app.setErrorHandler((err: unknown, req: FastifyRequest, reply: FastifyReply) => {
    const apiError = toApiError(err);
    // Only genuine surprises get a stack trace. A 503 for an integration that
    // is simply not configured is an expected answer, not an incident, and
    // logging it at error level would bury the real failures.
    if (apiError.code === 'unavailable') {
      req.log.warn({ code: apiError.code, msg: apiError.message }, 'request unavailable');
    } else if (apiError.status >= 500) {
      req.log.error({ err, code: apiError.code }, 'request failed');
    } else {
      req.log.debug({ code: apiError.code, msg: apiError.message }, 'request rejected');
    }
    // The reply may already be hijacked by an SSE handler; nothing to send then.
    if (reply.raw.headersSent) return;
    void sendError(reply, apiError);
  });

  app.setNotFoundHandler((req: FastifyRequest, reply: FastifyReply) => {
    void sendError(reply, new ApiError('not_found', `No route for ${req.method} ${req.url}.`));
  });
}
