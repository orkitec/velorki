// SPDX-License-Identifier: AGPL-3.0-only
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createOpenAICompatible } from '@ai-sdk/openai-compatible';
import type { LanguageModel } from 'ai';
import type { Config } from '@/config';
import { ApiError } from '@/server/errors';
import type { Counters } from '@/server/counters';

/**
 * The single place where a language model is constructed. Everything else in
 * the service takes a `ModelFactory`, which is what lets tests inject a mock
 * model without touching the network.
 */
export type ModelFactory = () => LanguageModel;

export function createModelFactory(config: Config): ModelFactory {
  return function getModel(): LanguageModel {
    if (!config.LLM_BASE_URL || !config.LLM_MODEL) {
      throw new ApiError('unavailable', 'AI features are not configured on this server.');
    }
    const provider = createOpenAICompatible({
      name: 'llm',
      baseURL: config.LLM_BASE_URL,
      // Self-hosted servers often accept any key; only send one if configured.
      ...(config.LLM_API_KEY === undefined ? {} : { apiKey: config.LLM_API_KEY }),
    });
    return provider(config.LLM_MODEL);
  };
}

/* -------------------------------------------------------------------------- */
/* System prompts                                                             */
/* -------------------------------------------------------------------------- */

export interface Prompts {
  plan: string;
  describe: string;
}

/**
 * The prompts are read from the source tree at runtime, not bundled: editing a
 * prompt must not need a code change. `next build` traces them into the
 * standalone output through `outputFileTracingIncludes`, and the standalone
 * server runs with the project root as its cwd.
 */
export const PROMPT_DIR = join(process.cwd(), 'src', 'ai', 'prompts');

/** Drop the SPDX HTML comment so it never becomes part of the system prompt. */
function stripLicenseHeader(text: string): string {
  return text.replace(/^<!--[\s\S]*?-->\s*/, '').trim();
}

/**
 * Prompts are read once per process: they are part of the deployed artifact,
 * and a missing prompt file should fail loudly rather than quietly.
 */
export function loadPrompts(dir: string = PROMPT_DIR): Prompts {
  return {
    plan: stripLicenseHeader(readFileSync(join(dir, 'plan.v1.md'), 'utf8')),
    describe: stripLicenseHeader(readFileSync(join(dir, 'describe.v1.md'), 'utf8')),
  };
}

/* -------------------------------------------------------------------------- */
/* Daily spend budget                                                         */
/* -------------------------------------------------------------------------- */

/** Spend is counted in micro-USD so the shared counter stays an integer. */
const MICRO = 1_000_000;
/** Two days, so yesterday's key is still readable just after UTC midnight. */
const SPEND_TTL_S = 2 * 24 * 60 * 60;

export function spendKey(now: number): string {
  return `llm:spend:${new Date(now).toISOString().slice(0, 10)}`;
}

/**
 * Coarse global cost guard. Token prices are configured per 1k tokens; the
 * running total is a counter per UTC day and therefore shared by every worker.
 * This is a circuit breaker for a runaway bill, not accounting: the hard
 * ceiling belongs at the provider.
 */
export class DailyBudget {
  readonly #budgetMicroUsd: number | undefined;
  readonly #usdPer1kIn: number;
  readonly #usdPer1kOut: number;
  readonly #counters: Counters;
  readonly #now: () => number;

  constructor(config: Config, counters: Counters, now: () => number = Date.now) {
    this.#budgetMicroUsd =
      config.LLM_DAILY_BUDGET_USD === undefined
        ? undefined
        : Math.round(config.LLM_DAILY_BUDGET_USD * MICRO);
    this.#usdPer1kIn = config.LLM_USD_PER_1K_IN;
    this.#usdPer1kOut = config.LLM_USD_PER_1K_OUT;
    this.#counters = counters;
    this.#now = now;
  }

  async spentUsd(): Promise<number> {
    const micro = (await this.#counters.get<number>(spendKey(this.#now()))) ?? 0;
    return micro / MICRO;
  }

  /** True when the estimated spend for the current UTC day is over budget. */
  async exceeded(): Promise<boolean> {
    if (this.#budgetMicroUsd === undefined) return false;
    const micro = (await this.#counters.get<number>(spendKey(this.#now()))) ?? 0;
    return micro >= this.#budgetMicroUsd;
  }

  async record(inputTokens: number, outputTokens: number): Promise<void> {
    const usd =
      (inputTokens / 1000) * this.#usdPer1kIn + (outputTokens / 1000) * this.#usdPer1kOut;
    const micro = Math.round(usd * MICRO);
    if (micro <= 0) return;
    await this.#counters.incr(spendKey(this.#now()), micro, { ttlIfNew: SPEND_TTL_S });
  }
}
