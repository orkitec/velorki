// SPDX-License-Identifier: AGPL-3.0-only

/**
 * Tiny LRU cache with a per-entry TTL.
 *
 * Uses the insertion-order guarantee of Map: re-inserting a key on read moves
 * it to the end, so the first key returned by keys() is always the least
 * recently used one.
 */
export class LruCache<V> {
  readonly #max: number;
  readonly #map = new Map<string, { value: V; expiresAt: number }>();
  readonly #now: () => number;

  constructor(max: number, now: () => number = Date.now) {
    if (max <= 0) throw new Error('LruCache max must be > 0');
    this.#max = max;
    this.#now = now;
  }

  get size(): number {
    return this.#map.size;
  }

  get(key: string): V | undefined {
    const entry = this.#map.get(key);
    if (entry === undefined) return undefined;
    if (entry.expiresAt <= this.#now()) {
      this.#map.delete(key);
      return undefined;
    }
    // Refresh recency.
    this.#map.delete(key);
    this.#map.set(key, entry);
    return entry.value;
  }

  set(key: string, value: V, ttlMs: number): void {
    if (this.#map.has(key)) this.#map.delete(key);
    this.#map.set(key, { value, expiresAt: this.#now() + ttlMs });
    while (this.#map.size > this.#max) {
      const oldest = this.#map.keys().next();
      if (oldest.done === true) break;
      this.#map.delete(oldest.value);
    }
  }

  delete(key: string): void {
    this.#map.delete(key);
  }

  clear(): void {
    this.#map.clear();
  }
}
