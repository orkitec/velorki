// SPDX-License-Identifier: AGPL-3.0-only
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';
import { POST as aiPlan } from '@/app/(api)/ai/plan/route';
import {
  CONSENT,
  jsonRequest,
  mockTextStreamModel,
  mockToolCallModel,
  usage,
  withEnv,
  type TestOptions,
} from '../helpers';

/**
 * The SSE contract, replayed from openapi.yaml.
 *
 * These are not "close enough" assertions: the documented examples are what an
 * app author writes their parser against, so the stream has to come out of the
 * handler byte for byte. The one difference is structural, not observable: a
 * YAML block scalar keeps a single trailing newline, while the wire format ends
 * every frame - the last one included - with a blank line.
 */

const URL_PLAN = 'https://api.velorki.com/ai/plan';
const MODEL_ID = 'some-model';

const llmEnv = { LLM_BASE_URL: 'http://llm.internal/v1', LLM_MODEL: MODEL_ID };

interface OpenApi {
  paths: {
    '/ai/plan': {
      post: {
        responses: {
          '200': {
            content: {
              'text/event-stream': {
                examples: Record<string, { value: string }>;
              };
            };
          };
        };
      };
    };
  };
}

const spec = parse(
  readFileSync(join(process.cwd(), 'openapi.yaml'), 'utf8'),
) as OpenApi;

const examples = spec.paths['/ai/plan'].post.responses['200'].content['text/event-stream'].examples;

/** The documented example, plus the blank line that terminates the last frame. */
function onTheWire(name: string): string {
  const value = examples[name]?.value;
  if (value === undefined) throw new Error(`openapi.yaml has no text/event-stream example "${name}"`);
  expect(value.endsWith('\n')).toBe(true);
  return `${value}\n`;
}

async function streamOf(body: unknown, opts: TestOptions): Promise<string> {
  return withEnv(
    llmEnv,
    async () => {
      const res = await aiPlan(jsonRequest(URL_PLAN, body, CONSENT));
      expect(res.status).toBe(200);
      expect(res.headers.get('content-type')).toBe('text/event-stream; charset=utf-8');
      return res.text();
    },
    opts,
  );
}

const PLAN_BODY = {
  step: 'plan',
  locale: 'de-CH',
  units: 'metric',
  prompt: 'Eine hügelige Runde von etwa 65 km mit einem Kaffeehalt.',
  context: { start: { lat: 47.38, lon: 8.54 }, start_label: 'Zürich', today: '2026-09-12' },
};

const PROPOSED_ROUTE = {
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

describe('the documented SSE streams', () => {
  it('replays the step=plan example byte for byte', async () => {
    const stream = await streamOf(PLAN_BODY, {
      getModel: () => mockToolCallModel(PROPOSED_ROUTE, usage(412, 96), MODEL_ID),
    });
    expect(stream).toBe(onTheWire('plan'));
  });

  it('replays the step=describe example byte for byte', async () => {
    const stream = await streamOf(
      {
        step: 'describe',
        locale: 'de-CH',
        units: 'metric',
        prompt: 'Beschreibe diese Route.',
        route_summary: {
          distance_km: 64.2,
          ascent_m: 810,
          surface: { paved: 0.8, gravel: 0.2 },
          waypoints: ['Uetliberg', 'Albispass'],
          highlights: ['Aussicht über den Zürichsee'],
        },
      },
      { getModel: () => mockTextStreamModel(['Diese Runde führt '], usage(300, 110), MODEL_ID) },
    );
    expect(stream).toBe(onTheWire('describe'));
  });

  it('replays the failure example byte for byte', async () => {
    const stream = await streamOf(PLAN_BODY, {
      getModel: () =>
        mockToolCallModel({ ...PROPOSED_ROUTE, distance_km: 2 }, usage(412, 96), MODEL_ID),
    });
    expect(stream).toBe(onTheWire('failure'));
  });
});
