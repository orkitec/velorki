// SPDX-License-Identifier: AGPL-3.0-only
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { AppContext } from '../app.js';
import { llmConfigured } from '../config.js';
import { ApiError, toApiError } from '../plugins/errors.js';
import { appUserId, requireEntitlement } from '../plugins/entitlement.js';
import { clientIp, rateLimit } from '../plugins/ratelimit.js';
import { firstHeaderValue } from '../plugins/requestid.js';
import { LIMITS } from '../util/tokenbucket.js';
import { SseStream } from '../util/sse.js';
import { planRequestSchema } from '../ai/schema.js';
import { PlanToolError, runPlan } from '../ai/plan.js';
import { runDescribe } from '../ai/describe.js';

export const CONSENT_HEADER = 'x-ai-consent';

/**
 * Sending a rider's free text to a third-party model is a privacy decision the
 * rider has to make, so the app must assert the consent it collected on every
 * single request. There is no server-side "remembered" consent.
 */
function requireConsent(req: FastifyRequest): void {
  if (firstHeaderValue(req.headers[CONSENT_HEADER]) !== '1') {
    throw new ApiError('consent_required', 'AI features require the rider to consent first.');
  }
}

export function registerAiRoutes(app: FastifyInstance, ctx: AppContext): void {
  const entitled = requireEntitlement(ctx.entitlement);

  const consentPreHandler = async (req: FastifyRequest, _reply: FastifyReply): Promise<void> => {
    requireConsent(req);
  };

  app.post(
    '/ai/plan',
    {
      preHandler: [
        entitled,
        consentPreHandler,
        // Per rider first, then a looser per-IP cap that catches many accounts
        // coming from one place.
        rateLimit(ctx.limiter, [LIMITS.aiPlanPerHour, LIMITS.aiPlanPerDay], (req) => appUserId(req)),
        rateLimit(ctx.limiter, [LIMITS.aiPlanPerIpHour], (req) =>
          clientIp(req, ctx.config.TRUST_PROXY),
        ),
      ],
    },
    async (req, reply) => {
      /* ---- everything that can still be answered with a plain JSON error ---- */

      if (!llmConfigured(ctx.config)) {
        throw new ApiError('unavailable', 'AI features are not configured on this server.');
      }
      if (ctx.budget.exceeded) {
        req.log.warn({ spentUsd: ctx.budget.spentUsd }, 'daily llm budget exhausted');
        throw new ApiError('unavailable', 'The daily AI budget for this server is exhausted.');
      }

      const parsed = planRequestSchema.safeParse(req.body);
      if (!parsed.success) {
        throw new ApiError(
          'invalid_request',
          parsed.error.issues
            .map((i) => `${i.path.join('.') || '(body)'}: ${i.message}`)
            .join('; '),
        );
      }
      const body = parsed.data;
      const model = ctx.getModel();

      /* ---- from here on the response is an SSE stream --------------------- */

      const sse = new SseStream(reply, String(req.id));

      // If the rider closes the app mid-stream, stop paying for tokens.
      const abort = new AbortController();
      req.raw.on('close', () => {
        if (!sse.closed) abort.abort();
      });

      try {
        if (body.step === 'plan') {
          const result = await runPlan({
            model,
            system: ctx.prompts.plan,
            body,
            abortSignal: abort.signal,
          });
          // The app turns these arguments into a BRouter query.
          sse.send('route_request', result.route);
          ctx.budget.record(result.usage.in, result.usage.out);
          sse.send('done', { usage: result.usage, model: result.model });
        } else {
          const result = await runDescribe({
            model,
            system: ctx.prompts.describe,
            body,
            abortSignal: abort.signal,
            onDelta: (delta) => {
              sse.send('text', { delta });
            },
          });
          ctx.budget.record(result.usage.in, result.usage.out);
          sse.send('done', { usage: result.usage, model: result.model });
        }
      } catch (err) {
        // Once the stream is open the status code is already 200, so failures
        // are reported as an `error` event carrying the normal error body.
        const apiError =
          err instanceof PlanToolError
            ? new ApiError('invalid_request', err.message)
            : err instanceof ApiError
              ? err
              : new ApiError('upstream_error', 'The model request failed.');
        if (apiError.status >= 500) {
          req.log.error({ err }, 'ai/plan failed');
        } else {
          req.log.info({ code: apiError.code }, 'ai/plan rejected');
        }
        sse.send('error', apiError.toBody());
      } finally {
        sse.end();
      }

      // The reply was hijacked; tell Fastify not to expect a payload.
      return reply;
    },
  );

  // Defensive: an error thrown after hijacking must not crash the process.
  app.addHook('onError', async (req, reply, err) => {
    if (reply.raw.headersSent && req.url.startsWith('/ai/')) {
      req.log.error({ err, code: toApiError(err).code }, 'error after ai stream started');
    }
  });
}
