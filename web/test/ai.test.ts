// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import { pino } from 'pino';
import { MockLanguageModelV4 } from 'ai/test';
import { injectSingletons } from '@/server/singletons';
import { POST as aiPlan } from '@/app/(api)/ai/plan/route';
import { buildPlanPrompt } from '@/ai/plan';
import { planRequestSchema } from '@/ai/schema';
import {
  AUTH,
  CONSENT,
  errOf,
  jsonRequest,
  mockFailingModel,
  mockTextStreamModel,
  mockToolCallModel,
  parseSse,
  withEnv,
  type TestOptions,
} from './helpers';

const URL_PLAN = 'https://api.velorki.com/ai/plan';

const llmEnv = {
  LLM_BASE_URL: 'http://llm.internal/v1',
  LLM_API_KEY: 'sk-test',
  LLM_MODEL: 'some-model',
};

const VALID_ROUTE = {
  distance_km: 65,
  loop: true,
  start: { use_current: true },
  via: ['Uetliberg'],
  surface: 'mixed',
  hills: 'seek',
  traffic_tolerance: 'low',
  stops: ['cafe'],
  profile_hint: 'trekking',
  notes: 'Hügelige Runde ab deinem Standort.',
  confidence: 0.8,
};

function planBody(extra: Record<string, unknown> = {}) {
  return {
    step: 'plan',
    locale: 'de-CH',
    units: 'metric',
    prompt: 'Eine hügelige Runde von etwa 65 km mit einem Kaffeehalt.',
    context: { start: { lat: 47.376887, lon: 8.541694 }, today: '2026-09-12' },
    ...extra,
  };
}

function call(body: unknown, headers: Record<string, string> = CONSENT): Promise<Response> {
  return aiPlan(jsonRequest(URL_PLAN, body, headers));
}

function withLlm<T>(
  env: Record<string, string>,
  opts: TestOptions,
  fn: () => Promise<T>,
): Promise<T> {
  return withEnv({ ...llmEnv, ...env }, fn, opts);
}

describe('POST /ai/plan: gating', () => {
  it('requires the consent header', async () => {
    await withLlm({}, { getModel: () => mockToolCallModel(VALID_ROUTE) }, async () => {
      const res = await call(planBody(), AUTH);
      expect(res.status).toBe(403);
      expect((await errOf(res)).code).toBe('consent_required');
    });
  });

  it('rejects a consent header that is not exactly "1"', async () => {
    await withLlm({}, { getModel: () => mockToolCallModel(VALID_ROUTE) }, async () => {
      for (const value of ['0', 'true', 'yes']) {
        const res = await call(planBody(), { ...AUTH, 'x-ai-consent': value });
        expect(res.status, value).toBe(403);
      }
    });
  });

  it('requires authentication before consent', async () => {
    await withLlm(
      { REVENUECAT_MODE: 'live', REVENUECAT_SECRET_KEY: 'sk' },
      { getModel: () => mockToolCallModel(VALID_ROUTE) },
      async () => {
        const res = await call(planBody(), {});
        expect(res.status).toBe(401);
      },
    );
  });

  it('degrades to 503 when no LLM is configured', async () => {
    await withEnv(
      {},
      async () => {
        const res = await call(planBody());
        expect(res.status).toBe(503);
        expect((await errOf(res)).code).toBe('unavailable');
      },
      { getModel: () => mockToolCallModel(VALID_ROUTE) },
    );
  });

  it('returns 503 once the daily budget is spent', async () => {
    await withLlm(
      {
        LLM_DAILY_BUDGET_USD: '0.0001',
        LLM_USD_PER_1K_IN: '1',
        LLM_USD_PER_1K_OUT: '2',
      },
      { getModel: () => mockToolCallModel(VALID_ROUTE) },
      async () => {
        const first = await call(planBody());
        expect(first.status).toBe(200);
        // Draining the stream is what records the spend.
        await first.text();

        // The first call recorded 120 in / 40 out tokens, well over $0.0001.
        const second = await call(planBody());
        expect(second.status).toBe(503);
        expect((await errOf(second)).code).toBe('unavailable');
      },
    );
  });

  it('rejects an invalid body with 400', async () => {
    await withLlm({}, { getModel: () => mockToolCallModel(VALID_ROUTE) }, async () => {
      for (const payload of [
        { step: 'nope', prompt: 'x' },
        { step: 'plan', prompt: '' },
        { step: 'plan', prompt: 'x'.repeat(1001) },
        // describe without a route_summary
        { step: 'describe', prompt: 'x' },
      ]) {
        const res = await call(payload);
        expect(res.status, JSON.stringify(payload)).toBe(400);
        expect((await errOf(res)).code).toBe('invalid_request');
      }
    });
  });

  it('charges the per-IP limit before the body is read', async () => {
    await withLlm(
      { TRUST_PROXY: '1', CLIENT_IP_HEADER: 'cf-connecting-ip' },
      { getModel: () => mockToolCallModel(VALID_ROUTE) },
      async () => {
        // One address, a different rider each time, so only the per-IP window
        // fills up. The body is one a reader would reject with 400.
        const bad = (rider: number) =>
          call({ step: 'nope' }, {
            ...CONSENT,
            authorization: `Bearer rider-${String(rider)}`,
            'cf-connecting-ip': '203.0.113.9',
          });

        for (let i = 0; i < 60; i += 1) {
          expect((await bad(i)).status, `call ${String(i)}`).toBe(400);
        }
        // Over the limit the same body answers 429: the request is refused
        // before anything is read, so it never gets as far as being invalid.
        const limited = await bad(60);
        expect(limited.status).toBe(429);
        expect((await errOf(limited)).code).toBe('rate_limited');

        // Another address still has its whole window.
        const other = await call({ step: 'nope' }, {
          ...CONSENT,
          'cf-connecting-ip': '198.51.100.1',
        });
        expect(other.status).toBe(400);
      },
    );
  });

  it('refuses a budget without prices at load time', async () => {
    const { loadConfig } = await import('@/config');
    expect(() => loadConfig({ LLM_DAILY_BUDGET_USD: '5' })).toThrow(/LLM_USD_PER_1K_IN/);
    expect(() => loadConfig({ LLM_DAILY_BUDGET_USD: '5', LLM_USD_PER_1K_IN: '1' })).toThrow(
      /LLM_USD_PER_1K_OUT/,
    );
    expect(() =>
      loadConfig({ LLM_DAILY_BUDGET_USD: '5', LLM_USD_PER_1K_IN: '1', LLM_USD_PER_1K_OUT: '2' }),
    ).not.toThrow();
  });
});

describe('POST /ai/plan: cache policy', () => {
  /**
   * `withApi` stamps `no-store` on every api answer that brings no policy of
   * its own, and the proxy sets none at all on a handler response. The SSE
   * headers must therefore reach the client exactly as `sseResponse` wrote
   * them: `no-store` would let a proxy buffer or refuse the stream.
   */
  it('keeps the SSE cache headers through withApi', async () => {
    await withLlm({}, { getModel: () => mockToolCallModel(VALID_ROUTE) }, async () => {
      const res = await call(planBody());
      expect(res.status).toBe(200);
      expect(res.headers.get('cache-control')).toBe('no-cache, no-transform');
      await res.text();
    });
  });

  it('still stamps no-store on the JSON errors of the same route', async () => {
    await withLlm({}, { getModel: () => mockToolCallModel(VALID_ROUTE) }, async () => {
      const res = await call(planBody(), AUTH);
      expect(res.status).toBe(403);
      expect(res.headers.get('cache-control')).toBe('no-store');
    });
  });
});

describe('POST /ai/plan: step=plan', () => {
  it('emits route_request from the tool call and ends with done', async () => {
    const model = mockToolCallModel(VALID_ROUTE);
    await withLlm({}, { getModel: () => model }, async () => {
      const res = await call(planBody());

      expect(res.status).toBe(200);
      expect(res.headers.get('content-type')).toBe('text/event-stream; charset=utf-8');
      expect(res.headers.get('cache-control')).toBe('no-cache, no-transform');
      expect(res.headers.get('x-accel-buffering')).toBe('no');
      expect(res.headers.get('x-request-id')).toBeTruthy();

      const payload = await res.text();
      expect(payload.startsWith(': open\n\n')).toBe(true);

      const events = parseSse(payload);
      expect(events.map((e) => e.event)).toEqual(['route_request', 'done']);
      expect(events[0]?.data).toMatchObject({
        distance_km: 65,
        loop: true,
        surface: 'mixed',
        hills: 'seek',
        profile_hint: 'trekking',
        via: ['Uetliberg'],
        stops: ['cafe'],
      });
      expect(events.at(-1)).toEqual({
        event: 'done',
        data: { usage: { in: 120, out: 40 }, model: 'mock-plan-model' },
      });
    });
  });

  it('forces the propose_route tool call', async () => {
    const model = mockToolCallModel(VALID_ROUTE);
    await withLlm({}, { getModel: () => model }, async () => {
      await (await call(planBody())).text();
      const generateCall = model.doGenerateCalls[0];
      expect(generateCall?.toolChoice).toEqual({ type: 'required' });
      expect(generateCall?.tools?.map((t) => t.name)).toEqual(['propose_route']);
    });
  });

  it('rounds the start coordinates and never includes the app_user_id', async () => {
    const model = mockToolCallModel(VALID_ROUTE);
    await withLlm({}, { getModel: () => model }, async () => {
      await (await call(planBody())).text();
      const serialized = JSON.stringify(model.doGenerateCalls[0]?.prompt);
      expect(serialized).toContain('47.38, 8.54');
      expect(serialized).not.toContain('47.376887');
      expect(serialized).not.toContain('user-42');
    });
  });

  it('emits an invalid_request error event when the tool args are unusable', async () => {
    // distance_km is below the schema minimum of 5.
    await withLlm(
      {},
      { getModel: () => mockToolCallModel({ ...VALID_ROUTE, distance_km: 2 }) },
      async () => {
        const events = parseSse(await (await call(planBody())).text());
        expect(events.at(-1)?.event).toBe('error');
        expect((events.at(-1)?.data as { error: { code: string } }).error.code).toBe(
          'invalid_request',
        );
      },
    );
  });

  it('emits an error event when the model answers without a tool call', async () => {
    await withLlm({}, { getModel: () => mockFailingModel() }, async () => {
      const events = parseSse(await (await call(planBody())).text());
      expect(events.map((e) => e.event)).not.toContain('done');
      expect(events.at(-1)?.event).toBe('error');
    });
  });

  it('treats a client disconnect as a shutdown, not a failure', async () => {
    const controller = new AbortController();
    const lines: string[] = [];
    const logger = pino({ level: 'debug', base: {} }, { write: (line: string) => lines.push(line) });

    // A model that only settles when the call is aborted, exactly as a real
    // provider does when the rider closes the app mid-plan.
    const hanging = new MockLanguageModelV4({
      modelId: 'mock-hanging-model',
      doGenerate: async ({ abortSignal }) =>
        new Promise((_resolve, reject) => {
          const fail = (): void => {
            reject(new DOMException('This operation was aborted', 'AbortError'));
          };
          // Already aborted on a retry: an abort listener would never fire.
          if (abortSignal?.aborted === true) fail();
          else abortSignal?.addEventListener('abort', fail, { once: true });
        }),
    });

    await withLlm({}, { getModel: () => hanging }, async () => {
      injectSingletons({ logger });
      const res = await aiPlan(
        new Request(URL_PLAN, {
          method: 'POST',
          headers: { 'content-type': 'application/json', ...CONSENT },
          body: JSON.stringify(planBody()),
          signal: controller.signal,
        }),
      );

      const reader = res.body!.getReader();
      const decoder = new TextDecoder();
      let body = '';
      // The ': open' preamble proves the stream is live before we disconnect.
      const first = await reader.read();
      body += decoder.decode(first.value);
      expect(body).toBe(': open\n\n');

      controller.abort();
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        body += decoder.decode(value);
      }

      // Nobody is listening any more, so no error event is written...
      expect(body).not.toContain('event: error');
      // ...and the abort is not reported as an incident.
      const errorLines = lines.filter((line) => (JSON.parse(line) as { level: number }).level >= 50);
      expect(errorLines).toEqual([]);
      expect(lines.some((line) => line.includes('ai/plan aborted by the client'))).toBe(true);
    });
  });
});

describe('POST /ai/plan: step=describe', () => {
  it('streams text deltas and ends with done', async () => {
    await withLlm(
      {},
      { getModel: () => mockTextStreamModel(['Eine ', 'schoene ', 'Runde.']) },
      async () => {
        const res = await call({
          step: 'describe',
          locale: 'de-CH',
          units: 'metric',
          prompt: 'Beschreibe die Route.',
          route_summary: {
            distance_km: 64.2,
            ascent_m: 810,
            surface: { paved: 0.8, gravel: 0.2 },
            waypoints: ['Uetliberg'],
            highlights: ['Aussicht'],
          },
        });

        expect(res.status).toBe(200);
        const events = parseSse(await res.text());
        expect(events.map((e) => e.event)).toEqual(['text', 'text', 'text', 'done']);
        expect(
          events
            .slice(0, 3)
            .map((e) => (e.data as { delta: string }).delta)
            .join(''),
        ).toBe('Eine schoene Runde.');
        expect(events.at(-1)).toEqual({
          event: 'done',
          data: { usage: { in: 90, out: 70 }, model: 'mock-describe-model' },
        });
      },
    );
  });
});

describe('prompt building', () => {
  it('applies the documented defaults to the request', () => {
    const parsed = planRequestSchema.parse({ step: 'plan', prompt: 'a flat 30 km loop' });
    expect(parsed.locale).toBe('en');
    expect(parsed.units).toBe('metric');
  });

  it('rejects a non-BCP47 locale', () => {
    expect(
      planRequestSchema.safeParse({ step: 'plan', prompt: 'x', locale: 'not a locale!' }).success,
    ).toBe(false);
  });

  it('never puts a raw coordinate in the prompt', () => {
    const body = planRequestSchema.parse({
      step: 'plan',
      prompt: 'ride',
      context: { start: { lat: 47.376887, lon: 8.541694 } },
    });
    const prompt = buildPlanPrompt(body);
    expect(prompt).toContain('47.38, 8.54');
    expect(prompt).not.toContain('376887');
  });
});
