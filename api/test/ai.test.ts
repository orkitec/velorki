// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import { buildPlanPrompt } from '../src/ai/plan.js';
import { planRequestSchema } from '../src/ai/schema.js';
import { loadPrompts } from '../src/ai/provider.js';
import {
  AUTH,
  errOf,
  mockFailingModel,
  mockTextStreamModel,
  mockToolCallModel,
  parseSse,
  testApp,
} from './helpers.js';

const llmEnv = {
  LLM_BASE_URL: 'http://llm.internal/v1',
  LLM_API_KEY: 'sk-test',
  LLM_MODEL: 'some-model',
};

const CONSENT = { ...AUTH, 'x-ai-consent': '1' };

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

describe('POST /ai/plan: gating', () => {
  it('requires the consent header', async () => {
    const app = testApp({ env: llmEnv, getModel: () => mockToolCallModel(VALID_ROUTE) });
    const res = await app.inject({
      method: 'POST',
      url: '/ai/plan',
      headers: AUTH,
      payload: planBody(),
    });
    expect(res.statusCode).toBe(403);
    expect(errOf(res).code).toBe('consent_required');
    await app.close();
  });

  it('rejects a consent header that is not exactly "1"', async () => {
    const app = testApp({ env: llmEnv, getModel: () => mockToolCallModel(VALID_ROUTE) });
    for (const value of ['0', 'true', 'yes']) {
      const res = await app.inject({
        method: 'POST',
        url: '/ai/plan',
        headers: { ...AUTH, 'x-ai-consent': value },
        payload: planBody(),
      });
      expect(res.statusCode, value).toBe(403);
    }
    await app.close();
  });

  it('requires authentication before consent', async () => {
    const app = testApp({
      env: { ...llmEnv, REVENUECAT_MODE: 'live', REVENUECAT_SECRET_KEY: 'sk' },
      getModel: () => mockToolCallModel(VALID_ROUTE),
    });
    const res = await app.inject({ method: 'POST', url: '/ai/plan', payload: planBody() });
    expect(res.statusCode).toBe(401);
    await app.close();
  });

  it('degrades to 503 when no LLM is configured', async () => {
    const app = testApp({ getModel: () => mockToolCallModel(VALID_ROUTE) });
    const res = await app.inject({
      method: 'POST',
      url: '/ai/plan',
      headers: CONSENT,
      payload: planBody(),
    });
    expect(res.statusCode).toBe(503);
    expect(errOf(res).code).toBe('unavailable');
    await app.close();
  });

  it('returns 503 once the daily budget is spent', async () => {
    const app = testApp({
      env: {
        ...llmEnv,
        LLM_DAILY_BUDGET_USD: '0.0001',
        LLM_USD_PER_1K_IN: '1',
        LLM_USD_PER_1K_OUT: '2',
      },
      getModel: () => mockToolCallModel(VALID_ROUTE),
    });

    const first = await app.inject({
      method: 'POST',
      url: '/ai/plan',
      headers: CONSENT,
      payload: planBody(),
    });
    expect(first.statusCode).toBe(200);

    // The first call recorded 120 in / 40 out tokens, well over $0.0001.
    const second = await app.inject({
      method: 'POST',
      url: '/ai/plan',
      headers: CONSENT,
      payload: planBody(),
    });
    expect(second.statusCode).toBe(503);
    expect(errOf(second).code).toBe('unavailable');
    await app.close();
  });

  it('rejects an invalid body with 400', async () => {
    const app = testApp({ env: llmEnv, getModel: () => mockToolCallModel(VALID_ROUTE) });
    for (const payload of [
      { step: 'nope', prompt: 'x' },
      { step: 'plan', prompt: '' },
      { step: 'plan', prompt: 'x'.repeat(1001) },
      // describe without a route_summary
      { step: 'describe', prompt: 'x' },
    ]) {
      const res = await app.inject({ method: 'POST', url: '/ai/plan', headers: CONSENT, payload });
      expect(res.statusCode, JSON.stringify(payload)).toBe(400);
      expect(errOf(res).code).toBe('invalid_request');
    }
    await app.close();
  });
});

describe('POST /ai/plan: step=plan', () => {
  it('emits route_request from the tool call and ends with done', async () => {
    const model = mockToolCallModel(VALID_ROUTE);
    const app = testApp({ env: llmEnv, getModel: () => model });

    const res = await app.inject({
      method: 'POST',
      url: '/ai/plan',
      headers: CONSENT,
      payload: planBody(),
    });

    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/event-stream');

    const events = parseSse(res.payload);
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

    await app.close();
  });

  it('forces the propose_route tool call', async () => {
    const model = mockToolCallModel(VALID_ROUTE);
    const app = testApp({ env: llmEnv, getModel: () => model });
    await app.inject({ method: 'POST', url: '/ai/plan', headers: CONSENT, payload: planBody() });

    const call = model.doGenerateCalls[0];
    expect(call?.toolChoice).toEqual({ type: 'required' });
    expect(call?.tools?.map((t) => t.name)).toEqual(['propose_route']);
    await app.close();
  });

  it('rounds the start coordinates and never includes the app_user_id', async () => {
    const model = mockToolCallModel(VALID_ROUTE);
    const app = testApp({ env: llmEnv, getModel: () => model });
    await app.inject({ method: 'POST', url: '/ai/plan', headers: CONSENT, payload: planBody() });

    const serialized = JSON.stringify(model.doGenerateCalls[0]?.prompt);
    expect(serialized).toContain('47.38, 8.54');
    expect(serialized).not.toContain('47.376887');
    expect(serialized).not.toContain('user-42');
    await app.close();
  });

  it('emits an invalid_request error event when the tool args are unusable', async () => {
    // distance_km is below the schema minimum of 5.
    const app = testApp({
      env: llmEnv,
      getModel: () => mockToolCallModel({ ...VALID_ROUTE, distance_km: 2 }),
    });

    const res = await app.inject({
      method: 'POST',
      url: '/ai/plan',
      headers: CONSENT,
      payload: planBody(),
    });

    const events = parseSse(res.payload);
    expect(events.at(-1)?.event).toBe('error');
    expect((events.at(-1)?.data as { error: { code: string } }).error.code).toBe('invalid_request');
    await app.close();
  });

  it('emits an error event when the model answers without a tool call', async () => {
    const app = testApp({ env: llmEnv, getModel: () => mockFailingModel() });
    const res = await app.inject({
      method: 'POST',
      url: '/ai/plan',
      headers: CONSENT,
      payload: planBody(),
    });
    const events = parseSse(res.payload);
    expect(events.map((e) => e.event)).not.toContain('done');
    expect(events.at(-1)?.event).toBe('error');
    await app.close();
  });
});

describe('POST /ai/plan: step=describe', () => {
  it('streams text deltas and ends with done', async () => {
    const app = testApp({
      env: llmEnv,
      getModel: () => mockTextStreamModel(['Eine ', 'schoene ', 'Runde.']),
    });

    const res = await app.inject({
      method: 'POST',
      url: '/ai/plan',
      headers: CONSENT,
      payload: {
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
      },
    });

    expect(res.statusCode).toBe(200);
    const events = parseSse(res.payload);
    expect(events.map((e) => e.event)).toEqual(['text', 'text', 'text', 'done']);
    expect(events.slice(0, 3).map((e) => (e.data as { delta: string }).delta).join('')).toBe(
      'Eine schoene Runde.',
    );
    expect(events.at(-1)).toEqual({
      event: 'done',
      data: { usage: { in: 90, out: 70 }, model: 'mock-describe-model' },
    });
    await app.close();
  });
});

describe('prompt building', () => {
  it('loads both system prompts without their SPDX header', () => {
    const prompts = loadPrompts();
    expect(prompts.plan).toContain('propose_route');
    expect(prompts.describe).toContain('60 to 90 words');
    expect(prompts.plan.startsWith('<!--')).toBe(false);
    expect(prompts.describe.startsWith('<!--')).toBe(false);
  });

  it('applies the documented defaults to the request', () => {
    const parsed = planRequestSchema.parse({ step: 'plan', prompt: 'a flat 30 km loop' });
    expect(parsed.locale).toBe('en');
    expect(parsed.units).toBe('metric');
  });

  it('rejects a non-BCP47 locale', () => {
    expect(planRequestSchema.safeParse({ step: 'plan', prompt: 'x', locale: 'not a locale!' }).success).toBe(
      false,
    );
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
