// SPDX-License-Identifier: AGPL-3.0-only

/**
 * The tiny slice of shared state the relay needs across cluster workers:
 * rate-limit windows, the entitlement cache, the daily LLM spend and the
 * once-a-day sweep election.
 *
 * `OrkifyCounters` puts them on Orkify's cache (IPC-backed, so two workers see
 * the same numbers). `MemoryCounters` is the dev and test backend; both
 * implement the same three operations so nothing above this file knows which
 * one it is talking to.
 */
export interface Counters {
  /**
   * Add `delta` to `key` and return the new value. `ttlIfNew` (seconds) is
   * applied only when the key is created; later increments never extend it,
   * which is what makes a fixed window actually expire.
   */
  incr(key: string, delta?: number, opts?: { ttlIfNew?: number }): Promise<number>;
  get<T>(key: string): Promise<T | undefined>;
  /** `ttl` in seconds; omitted means "until evicted". */
  set(key: string, value: unknown, ttl?: number): Promise<void>;
}

interface Entry {
  value: unknown;
  /** Epoch ms, or undefined for "no expiry". */
  expiresAt?: number;
}

export interface MemoryCountersOptions {
  now?: () => number;
  /**
   * Backing map. Two MemoryCounters sharing one map behave like two cluster
   * workers on one cache, which is exactly what the rate-limit test needs.
   */
  store?: Map<string, Entry>;
}

export class MemoryCounters implements Counters {
  readonly #store: Map<string, Entry>;
  readonly #now: () => number;

  constructor(opts: MemoryCountersOptions = {}) {
    this.#store = opts.store ?? new Map<string, Entry>();
    this.#now = opts.now ?? Date.now;
  }

  #live(key: string): Entry | undefined {
    const entry = this.#store.get(key);
    if (entry === undefined) return undefined;
    if (entry.expiresAt !== undefined && entry.expiresAt <= this.#now()) {
      this.#store.delete(key);
      return undefined;
    }
    return entry;
  }

  async incr(key: string, delta = 1, opts: { ttlIfNew?: number } = {}): Promise<number> {
    const existing = this.#live(key);
    if (existing === undefined) {
      const entry: Entry = { value: delta };
      if (opts.ttlIfNew !== undefined) entry.expiresAt = this.#now() + opts.ttlIfNew * 1000;
      this.#store.set(key, entry);
      return delta;
    }
    const next = (typeof existing.value === 'number' ? existing.value : 0) + delta;
    // Keep the original expiry: a fixed window must not slide.
    existing.value = next;
    return next;
  }

  async get<T>(key: string): Promise<T | undefined> {
    return this.#live(key)?.value as T | undefined;
  }

  async set(key: string, value: unknown, ttl?: number): Promise<void> {
    const entry: Entry = { value };
    if (ttl !== undefined) entry.expiresAt = this.#now() + ttl * 1000;
    this.#store.set(key, entry);
  }

  /** Test helper: drop everything. */
  clear(): void {
    this.#store.clear();
  }
}

type OrkifyCache = {
  incr(key: string, delta?: number, options?: { ttlIfNew?: number }): Promise<number>;
  get<T>(key: string): T | undefined;
  getAsync<T>(key: string): Promise<T | undefined>;
  set(key: string, value: unknown, opts?: { ttl?: number }): void;
};

export class OrkifyCounters implements Counters {
  readonly #cache: OrkifyCache;

  constructor(cache: OrkifyCache) {
    this.#cache = cache;
  }

  async incr(key: string, delta = 1, opts: { ttlIfNew?: number } = {}): Promise<number> {
    return this.#cache.incr(key, delta, opts.ttlIfNew === undefined ? {} : { ttlIfNew: opts.ttlIfNew });
  }

  async get<T>(key: string): Promise<T | undefined> {
    return this.#cache.getAsync<T>(key);
  }

  async set(key: string, value: unknown, ttl?: number): Promise<void> {
    this.#cache.set(key, value, ttl === undefined ? {} : { ttl });
  }
}
