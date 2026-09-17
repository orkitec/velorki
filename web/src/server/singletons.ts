// SPDX-License-Identifier: AGPL-3.0-only
import { cache } from '@orkify/cache';
import { loadConfig, type Config } from '@/config';
import { ShareStore } from '@/share/store';
import {
  DailyBudget,
  createModelFactory,
  loadPrompts,
  type ModelFactory,
  type Prompts,
} from '@/ai/provider';
import { MemoryCounters, OrkifyCounters, type Counters } from './counters';
import { EntitlementService } from './entitlement';
import { createLogger, type Logger } from './log';

/**
 * Process-wide singletons, cached on `globalThis`.
 *
 * Next re-evaluates route modules on every hot reload and once per lambda-like
 * entry point; a SQLite handle, a pino instance and the counters backend must
 * survive that, or dev would leak file handles and the cache would reset under
 * the user's feet. Tests replace the whole bag through `injectSingletons()`.
 */
export interface Singletons {
  config: Config;
  counters: Counters;
  store: ShareStore;
  logger: Logger;
  entitlement: EntitlementService;
  getModel: ModelFactory;
  prompts: Prompts;
  budget: DailyBudget;
}

const KEY = Symbol.for('velorki.singletons');
type Holder = Record<symbol, Partial<Singletons> | undefined>;
const holder = globalThis as unknown as Holder;

function bag(): Partial<Singletons> {
  holder[KEY] ??= {};
  return holder[KEY];
}

export function getConfig(): Config {
  const b = bag();
  b.config ??= loadConfig();
  return b.config;
}

function createCounters(config: Config): Counters {
  // `cache` is a lazy proxy: importing it costs nothing and the underlying
  // client is only built when the orkify backend is actually used.
  return config.COUNTERS === 'memory' ? new MemoryCounters() : new OrkifyCounters(cache);
}

export function getCounters(): Counters {
  const b = bag();
  b.counters ??= createCounters(getConfig());
  return b.counters;
}

export function getStore(): ShareStore {
  const b = bag();
  b.store ??= new ShareStore(getConfig().SHARE_DB_PATH);
  return b.store;
}

export function getLogger(): Logger {
  const b = bag();
  b.logger ??= createLogger(getConfig());
  return b.logger;
}

export function getEntitlement(): EntitlementService {
  const b = bag();
  b.entitlement ??= new EntitlementService(getConfig(), getCounters());
  return b.entitlement;
}

export function getModelFactory(): ModelFactory {
  const b = bag();
  b.getModel ??= createModelFactory(getConfig());
  return b.getModel;
}

export function getPrompts(): Prompts {
  const b = bag();
  b.prompts ??= loadPrompts();
  return b.prompts;
}

export function getBudget(): DailyBudget {
  const b = bag();
  b.budget ??= new DailyBudget(getConfig(), getCounters());
  return b.budget;
}

/** Tests only: replace part of the bag. Anything left out is built lazily. */
export function injectSingletons(parts: Partial<Singletons>): void {
  Object.assign(bag(), parts);
}

/**
 * Tests only: drop everything. `closeStore` is false when the store was
 * injected and the test still owns it.
 */
export function resetSingletons(closeStore = true): void {
  const b = holder[KEY];
  if (closeStore && b?.store !== undefined) {
    try {
      b.store.close();
    } catch {
      // Already closed by the test.
    }
  }
  holder[KEY] = {};
}
