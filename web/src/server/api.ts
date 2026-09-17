// SPDX-License-Identifier: AGPL-3.0-only
import { ApiError, errorResponse, toApiError } from './errors';
import { requestIdFrom, REQUEST_ID_HEADER } from './requestid';
import { requestLogger, type Logger } from './log';
import { getLogger } from './singletons';

/**
 * The wrapper every API route handler is exported through.
 *
 * It is the Fastify relay's onRequest hook, error handler and default headers
 * in one function: mint or echo the request id, build the request-scoped
 * logger, turn anything thrown into the uniform JSON error body, and mark the
 * answer `no-store`. Handlers therefore only contain the part that differs.
 */

export interface ApiContext<P = unknown> {
  requestId: string;
  log: Logger;
  /** Next's route params, when the segment has any. */
  params?: Promise<P>;
}

export type ApiHandler<P = unknown> = (
  request: Request,
  ctx: ApiContext<P>,
) => Promise<Response>;

interface RouteContext<P> {
  params?: Promise<P>;
}

export function withApi<P = unknown>(
  handler: ApiHandler<P>,
): (request: Request, routeCtx?: RouteContext<P>) => Promise<Response> {
  return async function apiRoute(request, routeCtx) {
    const requestId = requestIdFrom(request.headers);
    const log = requestLogger(getLogger(), request.headers, requestId);

    let response: Response;
    try {
      const ctx: ApiContext<P> = { requestId, log };
      if (routeCtx?.params !== undefined) ctx.params = routeCtx.params;
      response = await handler(request, ctx);
    } catch (err) {
      const apiError = toApiError(err);
      logFailure(log, apiError, err);
      response = errorResponse(apiError);
    }

    return stamp(response, requestId);
  };
}

/**
 * Only genuine surprises get a stack trace. A 503 for an integration that is
 * simply not configured is an expected answer, not an incident, and logging it
 * at error level would bury the real failures.
 */
export function logFailure(log: Logger, apiError: ApiError, err: unknown): void {
  // `reason`, not `msg`: pino writes the log message itself as `msg`, so a
  // `msg` field in the merging object is emitted a second time and every JSON
  // parser keeps only the last one - the detail would be silently dropped.
  if (apiError.code === 'unavailable') {
    log.warn({ code: apiError.code, reason: apiError.message }, 'request unavailable');
  } else if (apiError.status >= 500) {
    log.error({ err, code: apiError.code }, 'request failed');
  } else {
    log.debug({ code: apiError.code, reason: apiError.message }, 'request rejected');
  }
}

/**
 * Add the request id and the api host's cache policy. An SSE response brings
 * its own `cache-control: no-cache, no-transform`, which must survive.
 */
function stamp(response: Response, requestId: string): Response {
  const headers = new Headers(response.headers);
  headers.set(REQUEST_ID_HEADER, requestId);
  if (!headers.has('cache-control')) headers.set('cache-control', 'no-store');
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

/** A JSON body with the content type the relay always sent. */
export function json(body: unknown, status = 200, extraHeaders: HeadersInit = {}): Response {
  const headers = new Headers(extraHeaders);
  headers.set('content-type', 'application/json; charset=utf-8');
  return new Response(JSON.stringify(body), { status, headers });
}
