// SPDX-License-Identifier: AGPL-3.0-only
import type { LanguageModelV4FinishReason, LanguageModelV4Usage } from '@ai-sdk/provider';
import { MockLanguageModelV4, simulateReadableStream } from 'ai/test';
import { loadConfig, type Config } from '@/config';
import type { ModelFactory } from '@/ai/provider';
import { DailyBudget, loadPrompts } from '@/ai/provider';
import { MemoryCounters } from '@/server/counters';
import { EntitlementService } from '@/server/entitlement';
import { createLogger } from '@/server/log';
import { injectSingletons, resetSingletons } from '@/server/singletons';
import { ShareStore } from '@/share/store';

export { resetSingletons };

/** Build a Config from an explicit env map, ignoring the real process env. */
export function testConfig(env: Record<string, string> = {}): Config {
  return loadConfig({
    PUBLIC_BASE_URL: 'https://share.velorki.test',
    SHARE_DB_PATH: ':memory:',
    REVENUECAT_MODE: 'stub',
    LOG_LEVEL: 'silent',
    COUNTERS: 'memory',
    ...env,
  });
}

export interface TestContext {
  config: Config;
  counters: MemoryCounters;
  store: ShareStore;
  /** Swap the model factory mid-test (the AI routes read it per request). */
  setModel: (factory: ModelFactory) => void;
}

export interface TestOptions {
  /** Injected clock, shared by the counters and the share store. */
  now?: () => number;
  store?: ShareStore;
  getModel?: ModelFactory;
  counters?: MemoryCounters;
}

/**
 * Install a fresh set of singletons built from `env` and run `fn` against them.
 *
 * The route handlers reach their dependencies through `@/server/singletons`,
 * so replacing that bag is the whole of the test wiring: an in-memory config,
 * `MemoryCounters` instead of Orkify's cache and a `:memory:` SQLite database.
 */
export async function withEnv<T>(
  env: Record<string, string>,
  fn: (ctx: TestContext) => Promise<T> | T,
  opts: TestOptions = {},
): Promise<T> {
  resetSingletons();
  const config = testConfig(env);
  const counters = opts.counters ?? new MemoryCounters(opts.now === undefined ? {} : { now: opts.now });
  const store = opts.store ?? new ShareStore(':memory:', opts.now);
  const logger = createLogger(config);

  let getModel: ModelFactory =
    opts.getModel ??
    (() => {
      throw new Error('no model factory injected into this test');
    });

  injectSingletons({
    config,
    counters,
    store,
    logger,
    entitlement: new EntitlementService(config, counters),
    getModel: () => getModel(),
    prompts: loadPrompts(),
    budget: new DailyBudget(config, counters, opts.now),
  });

  const ctx: TestContext = {
    config,
    counters,
    store,
    setModel: (factory) => {
      getModel = factory;
    },
  };

  try {
    return await fn(ctx);
  } finally {
    resetSingletons(opts.store === undefined);
  }
}

export const AUTH = { authorization: 'Bearer user-42' };
export const CONSENT = { ...AUTH, 'x-ai-consent': '1' };

/** Build a JSON request the way the app does. */
export function jsonRequest(
  url: string,
  body: unknown,
  headers: Record<string, string> = {},
  method = 'POST',
): Request {
  return new Request(url, {
    method,
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
}

export async function errOf(res: Response): Promise<ApiErrorBody> {
  const body = (await res.json()) as { error: ApiErrorBody };
  return body.error;
}

export async function bodyOf<T>(res: Response): Promise<T> {
  return (await res.json()) as T;
}

export interface ApiErrorBody {
  code: string;
  message: string;
  retry_after_s?: number;
}

export interface ShareCreated {
  id: string;
  url: string;
}

/* -------------------------------------------------------------------------- */
/* Mock language models                                                       */
/* -------------------------------------------------------------------------- */

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
 */
export function mockToolCallModel(
  input: unknown,
  tokens = usage(120, 40),
  modelId = 'mock-plan-model',
): MockLanguageModelV4 {
  return new MockLanguageModelV4({
    modelId,
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
export function mockTextStreamModel(
  chunks: string[],
  tokens = usage(90, 70),
  modelId = 'mock-describe-model',
): MockLanguageModelV4 {
  return new MockLanguageModelV4({
    modelId,
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
