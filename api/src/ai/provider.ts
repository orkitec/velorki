// SPDX-License-Identifier: AGPL-3.0-only
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createOpenAICompatible } from '@ai-sdk/openai-compatible';
import type { LanguageModel } from 'ai';
import type { Config } from '../config.js';
import { ApiError } from '../plugins/errors.js';

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

const PROMPT_DIR = join(import.meta.dirname, 'prompts');

/** Drop the SPDX HTML comment so it never becomes part of the system prompt. */
function stripLicenseHeader(text: string): string {
  return text.replace(/^<!--[\s\S]*?-->\s*/, '').trim();
}

/**
 * Prompts are read once at startup: they are part of the deployed artifact, and
 * a missing prompt file should fail the boot loudly rather than the first
 * request quietly.
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

/**
 * Coarse global cost guard. Token prices are configured per 1k tokens; the
 * running total resets at UTC midnight. This is a circuit breaker for a
 * runaway bill, not accounting: it is process-local and approximate.
 */
export class DailyBudget {
  readonly #budgetUsd: number | undefined;
  readonly #usdPer1kIn: number;
  readonly #usdPer1kOut: number;
  readonly #now: () => number;
  #day = '';
  #spentUsd = 0;

  constructor(config: Config, now: () => number = Date.now) {
    this.#budgetUsd = config.LLM_DAILY_BUDGET_USD;
    this.#usdPer1kIn = config.LLM_USD_PER_1K_IN;
    this.#usdPer1kOut = config.LLM_USD_PER_1K_OUT;
    this.#now = now;
  }

  get spentUsd(): number {
    this.#rollDay();
    return this.#spentUsd;
  }

  /** True when the estimated spend for the current UTC day is over budget. */
  get exceeded(): boolean {
    if (this.#budgetUsd === undefined) return false;
    this.#rollDay();
    return this.#spentUsd >= this.#budgetUsd;
  }

  record(inputTokens: number, outputTokens: number): void {
    this.#rollDay();
    this.#spentUsd +=
      (inputTokens / 1000) * this.#usdPer1kIn + (outputTokens / 1000) * this.#usdPer1kOut;
  }

  #rollDay(): void {
    const today = new Date(this.#now()).toISOString().slice(0, 10);
    if (today !== this.#day) {
      this.#day = today;
      this.#spentUsd = 0;
    }
  }
}
