// SPDX-License-Identifier: AGPL-3.0-only

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

/**
 * Map anything thrown inside a handler onto the uniform error body. The four
 * body-parsing failures already arrive as ApiError from `readJsonBody`; a bare
 * SyntaxError can still escape from a hand-rolled JSON.parse.
 */
export function toApiError(err: unknown): ApiError {
  if (err instanceof ApiError) return err;
  if (err instanceof SyntaxError) {
    return new ApiError('invalid_request', 'Request body is not valid JSON.');
  }
  return new ApiError('upstream_error', 'Internal server error.', { status: 500 });
}

/** Render an ApiError as the JSON response, including Retry-After. */
export function errorResponse(err: ApiError, extraHeaders: HeadersInit = {}): Response {
  const headers = new Headers(extraHeaders);
  headers.set('content-type', 'application/json; charset=utf-8');
  if (err.retryAfterS !== undefined) headers.set('retry-after', String(err.retryAfterS));
  return new Response(JSON.stringify(err.toBody()), { status: err.status, headers });
}

/** The 404 body every "nothing here" answer on the api host uses. */
export function notFoundResponse(message: string, extraHeaders: HeadersInit = {}): Response {
  return errorResponse(new ApiError('not_found', message), extraHeaders);
}
