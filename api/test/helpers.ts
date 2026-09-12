// SPDX-License-Identifier: AGPL-3.0-only
import type { LanguageModelV4FinishReason, LanguageModelV4Usage } from '@ai-sdk/provider';
import { MockLanguageModelV4, simulateReadableStream } from 'ai/test';
import { buildApp, type BuildAppOptions } from '../src/app.js';
import { loadConfig, type Config } from '../src/config.js';
import { ShareStore } from '../src/share/store.js';

/** Build a Config from an explicit env map, ignoring the real process env. */
export function testConfig(env: Record<string, string> = {}): Config {
  return loadConfig({
    PUBLIC_BASE_URL: 'https://share.velorki.test',
    SHARE_DB_PATH: ':memory:',
    REVENUECAT_MODE: 'stub',
    ...env,
  });
}

/**
 * Build an app wired for tests: silent logger, in-memory share store and,
 * unless overridden, the stub entitlement mode.
 */
export function testApp(opts: BuildAppOptions & { env?: Record<string, string> } = {}) {
  const { env, ...rest } = opts;
  const config = rest.config ?? testConfig(env);
  return buildApp({
    logger: false,
    config,
    shares: rest.shares ?? new ShareStore(':memory:'),
    ...rest,
  });
}

export const AUTH = { authorization: 'Bearer user-42' };

const zeroUsage: LanguageModelV4Usage = {
  inputTokens: { total: 0, noCache: 0, cacheRead: 0, cacheWrite: 0 },
  outputTokens: { total: 0, text: 0, reasoning: 0 },
};

/** The v4 provider spec carries a unified finish reason plus the raw one. */
function finish(unified: LanguageModelV4FinishReason['unified']): LanguageModelV4FinishReason {
  return { unified, raw: undefined };
}

export function usage(input: number, output: number): LanguageModelV4Usage {
  return {
    inputTokens: { total: input, noCache: input, cacheRead: 0, cacheWrite: 0 },
    outputTokens: { total: output, text: output, reasoning: 0 },
  };
}

/**
 * A mock model that answers every generate call with one `propose_route` tool
 * call carrying `input`.
 *
 * The installed `ai` version (7.x) ships MockLanguageModelV4 rather than the
 * MockLanguageModelV2 of older releases; the provider spec is the only thing
 * that changed, the idea is the same.
 */
export function mockToolCallModel(input: unknown, tokens = usage(120, 40)): MockLanguageModelV4 {
  return new MockLanguageModelV4({
    modelId: 'mock-plan-model',
    doGenerate: async () => ({
      content: [
        {
          type: 'tool-call' as const,
          toolCallId: 'call-1',
          toolName: 'propose_route',
          input: JSON.stringify(input),
        },
      ],
      finishReason: finish('tool-calls'),
      usage: tokens,
      warnings: [],
    }),
  });
}

/** A mock model that streams the given text chunks and then finishes. */
export function mockTextStreamModel(chunks: string[], tokens = usage(90, 70)): MockLanguageModelV4 {
  return new MockLanguageModelV4({
    modelId: 'mock-describe-model',
    doStream: async () => ({
      stream: simulateReadableStream({
        chunkDelayInMs: null,
        initialDelayInMs: null,
        chunks: [
          { type: 'text-start' as const, id: 't1' },
          ...chunks.map((delta) => ({ type: 'text-delta' as const, id: 't1', delta })),
          { type: 'text-end' as const, id: 't1' },
          { type: 'finish' as const, finishReason: finish('stop'), usage: tokens },
        ],
      }),
    }),
  });
}

/** A mock model that refuses to work; used to exercise the error event. */
export function mockFailingModel(): MockLanguageModelV4 {
  return new MockLanguageModelV4({
    modelId: 'mock-broken-model',
    doGenerate: async () => ({
      content: [{ type: 'text' as const, text: 'I would rather not.' }],
      finishReason: finish('stop'),
      usage: zeroUsage,
      warnings: [],
    }),
  });
}

export interface SseEvent {
  event: string;
  data: unknown;
}

/** Parse an SSE response body into its events, ignoring comment frames. */
export function parseSse(body: string): SseEvent[] {
  const events: SseEvent[] = [];
  for (const block of body.split('\n\n')) {
    const lines = block.split('\n');
    const eventLine = lines.find((l) => l.startsWith('event: '));
    const dataLine = lines.find((l) => l.startsWith('data: '));
    if (eventLine === undefined || dataLine === undefined) continue;
    events.push({
      event: eventLine.slice('event: '.length),
      data: JSON.parse(dataLine.slice('data: '.length)) as unknown,
    });
  }
  return events;
}

/** A tiny but structurally valid GPX track. */
export function sampleGpx(points = 3): string {
  const trkpts = Array.from(
    { length: points },
    (_, i) => `<trkpt lat="${(47.4 + i * 0.01).toFixed(4)}" lon="${(8.5 + i * 0.01).toFixed(4)}"/>`,
  ).join('');
  return `<?xml version="1.0" encoding="UTF-8"?><gpx version="1.1" creator="velorki-test"><trk><name>Test</name><trkseg>${trkpts}</trkseg></trk></gpx>`;
}

/** Build a RevenueCat subscriber response with the given entitlement state. */
export function revenueCatResponse(
  entitlement: string,
  expiresDate: string | null | undefined,
): Response {
  const entitlements =
    expiresDate === undefined ? {} : { [entitlement]: { expires_date: expiresDate } };
  return new Response(JSON.stringify({ subscriber: { entitlements } }), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
}

/**
 * Read back one recorded call of a `vi.stubGlobal('fetch', ...)` mock.
 * Typed loosely on purpose: the mock's own signature carries no parameters.
 */
export function fetchCall(
  mock: { mock: { calls: [input?: unknown, init?: RequestInit][] } },
  index = 0,
): { url: string; init: RequestInit } {
  const call = mock.mock.calls[index];
  if (call === undefined) throw new Error(`no fetch call recorded at index ${String(index)}`);
  return { url: String(call[0]), init: call[1] ?? {} };
}

/**
 * `inject()` responses type their JSON body as `any`; these two helpers put a
 * type back on it so the tests stay under the type-checked lint rules.
 */
export function bodyOf<T>(res: { json: () => unknown }): T {
  return res.json() as T;
}

export interface ApiErrorBody {
  code: string;
  message: string;
  retry_after_s?: number;
}

export function errOf(res: { json: () => unknown }): ApiErrorBody {
  return (res.json() as { error: ApiErrorBody }).error;
}

export interface ShareCreated {
  id: string;
  url: string;
}
