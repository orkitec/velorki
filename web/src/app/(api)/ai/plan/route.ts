// SPDX-License-Identifier: AGPL-3.0-only
import { clientIp, llmConfigured } from '@/config';
import { withApi } from '@/server/api';
import { readJsonBody } from '@/server/body';
import { ApiError } from '@/server/errors';
import { requireEntitlement } from '@/server/entitlement';
import { LIMITS, enforce } from '@/server/ratelimit';
import { sseResponse } from '@/server/sse';
import {
  getBudget,
  getConfig,
  getCounters,
  getEntitlement,
  getModelFactory,
  getPrompts,
} from '@/server/singletons';
import { planRequestSchema } from '@/ai/schema';
import { PlanToolError, runPlan } from '@/ai/plan';
import { runDescribe } from '@/ai/describe';

export const CONSENT_HEADER = 'x-ai-consent';

/**
 * Sending a rider's free text to a third-party model is a privacy decision the
 * rider has to make, so the app must assert the consent it collected on every
 * single request. There is no server-side "remembered" consent.
 */
function requireConsent(headers: Headers): void {
  if (headers.get(CONSENT_HEADER) !== '1') {
    throw new ApiError('consent_required', 'AI features require the rider to consent first.');
  }
}

export const POST = withApi(async (request, ctx) => {
  const config = getConfig();
  const counters = getCounters();

  /* ---- everything that can still be answered with a plain JSON error ---- */

  const raw = await readJsonBody(request);
  const appUserId = await requireEntitlement(getEntitlement(), request.headers, ctx.log);
  requireConsent(request.headers);
  // Per rider first, then a looser per-IP cap that catches many accounts
  // coming from one place.
  await enforce(counters, appUserId, [LIMITS.aiPlanPerHour, LIMITS.aiPlanPerDay], ctx.log);
  await enforce(counters, clientIp(config, request.headers), [LIMITS.aiPlanPerIpHour], ctx.log);

  if (!llmConfigured(config)) {
    throw new ApiError('unavailable', 'AI features are not configured on this server.');
  }
  const budget = getBudget();
  if (await budget.exceeded()) {
    ctx.log.warn({ spentUsd: await budget.spentUsd() }, 'daily llm budget exhausted');
    throw new ApiError('unavailable', 'The daily AI budget for this server is exhausted.');
  }

  const parsed = planRequestSchema.safeParse(raw);
  if (!parsed.success) {
    throw new ApiError(
      'invalid_request',
      parsed.error.issues.map((i) => `${i.path.join('.') || '(body)'}: ${i.message}`).join('; '),
    );
  }
  const body = parsed.data;
  const model = getModelFactory()();
  const prompts = getPrompts();

  /* ---- from here on the response is an SSE stream --------------------- */

  return sseResponse({
    requestId: ctx.requestId,
    signal: request.signal,
    run: async (sse, abortSignal) => {
      try {
        if (body.step === 'plan') {
          const result = await runPlan({
            model,
            system: prompts.plan,
            body,
            abortSignal,
          });
          // The app turns these arguments into a BRouter query.
          sse.send('route_request', result.route);
          await budget.record(result.usage.in, result.usage.out);
          sse.send('done', { usage: result.usage, model: result.model });
        } else {
          const result = await runDescribe({
            model,
            system: prompts.describe,
            body,
            abortSignal,
            onDelta: (delta) => {
              sse.send('text', { delta });
            },
          });
          await budget.record(result.usage.in, result.usage.out);
          sse.send('done', { usage: result.usage, model: result.model });
        }
      } catch (err) {
        // A rider closing the app aborts the model call, which surfaces here
        // as an AbortError. That is the intended shutdown path, not an
        // incident: nobody is left to read an `error` event, and logging it at
        // error level with a stack would bury the real failures.
        if (abortSignal.aborted) {
          ctx.log.debug({ step: body.step }, 'ai/plan aborted by the client');
          return;
        }
        // Once the stream is open the status code is already 200, so failures
        // are reported as an `error` event carrying the normal error body.
        const apiError =
          err instanceof PlanToolError
            ? new ApiError('invalid_request', err.message)
            : err instanceof ApiError
              ? err
              : new ApiError('upstream_error', 'The model request failed.');
        if (apiError.status >= 500) {
          ctx.log.error({ err }, 'ai/plan failed');
        } else {
          ctx.log.info({ code: apiError.code }, 'ai/plan rejected');
        }
        sse.send('error', apiError.toBody());
      }
    },
  });
});
