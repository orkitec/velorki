// SPDX-License-Identifier: AGPL-3.0-only
import type { FastifyReply, FastifyRequest } from 'fastify';
import { ApiError } from './errors.js';
import { firstHeaderValue } from './requestid.js';
import type { LimitSpec, RateLimiter } from '../util/tokenbucket.js';

/**
 * Determine the client IP used as a rate-limit key.
 *
 * X-Forwarded-For is attacker-controlled unless a trusted proxy sets it, so it
 * is only consulted when TRUST_PROXY=1. The left-most entry is the original
 * client as appended by the first proxy.
 */
export function clientIp(req: FastifyRequest, trustProxy: boolean): string {
  if (trustProxy) {
    const value = firstHeaderValue(req.headers['x-forwarded-for']);
    if (value !== undefined) {
      const first = value.split(',')[0]?.trim();
      if (first !== undefined && first !== '') return first;
    }
  }
  return req.ip || 'unknown';
}

/**
 * Build a preHandler that consumes one token from each of `limits`.
 * `keyOf` decides whether the bucket is per-IP or per app_user_id.
 */
export function rateLimit(
  limiter: RateLimiter,
  limits: readonly LimitSpec[],
  keyOf: (req: FastifyRequest) => string,
) {
  return async function rateLimitPreHandler(req: FastifyRequest, _reply: FastifyReply): Promise<void> {
    const result = limiter.consume(keyOf(req), limits);
    if (!result.allowed) {
      req.log.info({ limit: result.limit?.name }, 'rate limited');
      throw new ApiError('rate_limited', 'Too many requests. Please slow down.', {
        retryAfterS: result.retryAfterS,
      });
    }
  };
}
