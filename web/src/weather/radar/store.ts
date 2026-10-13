// SPDX-License-Identifier: AGPL-3.0-only
import type { Counters } from '@/server/counters';
import { parseGrid, serialiseGrid, type ClassGrid } from './grid';
import { classesOfArea, encodeClassPng, type GridProjection, type MercatorBox } from './render';

/**
 * A radar composite the relay draws, fetched lazily from its publisher and
 * kept on this box; what tells one source from another is its
 * [RadarSource], the rest is the same for all:
 *
 * - The frames: the source's own list of the last [RadarSource.historyMs],
 *   asked for at most once a [LISTING_TTL_S] for the whole cluster, through
 *   the counters.
 * - A frame's grid: the first request that needs one fetches its file once,
 *   decodes it into the class grid (`grid.ts`) and puts it, deflated, into
 *   the cluster's shared cache (the counters, `@orkify/cache` in production)
 *   under a versioned key for [RadarSource.keepMs]; every later request, on
 *   any worker, reads it from there. In one worker a request already
 *   fetching is joined; across workers a lock in the counters lets one fetch
 *   while the others wait for its entry. A grid over [MAX_SHARED_BYTES] is
 *   not shared (the cache refuses values over 1 MB): each worker then keeps
 *   its own. A frame or a listing that failed is not asked for again for
 *   [FAIL_TTL_S], by any worker.
 * - In memory, per worker: the last [GRIDS_IN_MEMORY] grids decoded and the
 *   images drawn, up to [IMAGE_CACHE_BYTES].
 *
 * No timer and no cron: nothing is fetched that no rider asked for.
 */

/** How a source reaches its publisher: the store's fetch, its user agent, a timeout. */
export interface RadarUpstream {
  /**
   * `url` fetched with the relay's user agent besides `headers`, given up
   * after `timeoutMs`; a network failure throws [RadarUpstreamError].
   */
  request(
    url: string,
    init: {
      timeoutMs: number;
      method?: 'GET' | 'POST';
      headers?: Record<string, string>;
      body?: string;
      redirect?: RequestRedirect;
    },
  ): Promise<Response>;
}

/** One radar composite: where its frames come from and how they are read. */
export interface RadarSource<P> {
  /** The prefix of its cache keys and log lines: `opera`, `dpc`. */
  readonly name: string;
  /** What an image's box has to meet, said in a refusal: "the OPERA composite". */
  readonly label: string;
  /** The credit the app shows with the layer. */
  readonly attribution: string;
  /** The composite's step. */
  readonly stepMs: number;
  /** How far back the frames are offered. */
  readonly historyMs: number;
  /** How long a frame's grid stays in the shared cache. */
  readonly keepMs: number;
  /** The version of the shared grids, part of their keys. */
  readonly gridVersion: number;
  /** What a shared grid's bytes start with ([serialiseGrid]). */
  readonly gridFormat: string;
  /** The largest file accepted, bytes. */
  readonly maxFileBytes: number;
  /** The box an image request has to meet, Web Mercator. */
  readonly domain: MercatorBox;
  /** A frame's name in keys and logs, e.g. `20261012T2105`. */
  stamp(ms: number): string;
  /**
   * The frames the publisher has from `from` to `now`, epoch ms, in any
   * order; throws on a failure (an answer it cannot read included).
   */
  list(upstream: RadarUpstream, from: number, now: number): Promise<number[]>;
  /** The publisher's answer with frame `time`'s file; throws where it cannot be asked. */
  fetchFrame(upstream: RadarUpstream, time: number): Promise<Response>;
  /** The class grid of a frame's file; throws on anything it cannot read. */
  decode(bytes: Uint8Array): Promise<ClassGrid<P>>;
  /** The projection a grid's `proj` names, to draw it. */
  projection(proj: P): GridProjection;
}

const LISTING_TTL_S = 60;
/** How many frames one worker fetches from a publisher at once. */
const MAX_FETCHES = 2;
const LOCK_TTL_S = 60;
const LOCK_WAIT_MS = 30_000;
const LOCK_POLL_MS = 250;
/** How long a frame or a listing that failed is not asked for again. */
const FAIL_TTL_S = 30;
const GRIDS_IN_MEMORY = 2;
/**
 * The largest grid shared, deflated: under the cache's 1 MB a value, with
 * room for its serialisation.
 */
export const MAX_SHARED_BYTES = 1_000_000;
const IMAGE_CACHE_BYTES = 32 * 1024 * 1024;

/** A failure of a publisher: the route answers 502. */
export class RadarUpstreamError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'RadarUpstreamError';
  }
}

export interface RadarStoreOptions {
  counters: Counters;
  /** For tests; [MAX_SHARED_BYTES] otherwise. */
  maxSharedBytes?: number;
  userAgent: string;
  now?: () => number;
  /** For tests; `globalThis.fetch` at call time otherwise. */
  fetch?: typeof fetch;
  log?: { info: (obj: object, msg: string) => void; warn: (obj: object, msg: string) => void };
}

export class RadarStore<P> {
  readonly source: RadarSource<P>;
  readonly #maxSharedBytes: number;
  readonly #counters: Counters;
  readonly #userAgent: string;
  readonly #now: () => number;
  readonly #fetch: typeof fetch;
  readonly #log: RadarStoreOptions['log'];
  readonly #inFlight = new Map<number, Promise<ClassGrid<P>>>();
  readonly #grids = new Map<number, ClassGrid<P>>();
  readonly #images = new Map<string, Buffer>();
  #imageBytes = 0;
  #listing: { at: number; frames: number[] } | undefined;
  #listingInFlight: Promise<number[]> | undefined;
  #fetching = 0;
  readonly #queue: (() => void)[] = [];
  readonly #upstream: RadarUpstream;

  constructor(source: RadarSource<P>, opts: RadarStoreOptions) {
    this.source = source;
    this.#maxSharedBytes = opts.maxSharedBytes ?? MAX_SHARED_BYTES;
    this.#counters = opts.counters;
    this.#userAgent = opts.userAgent;
    this.#now = opts.now ?? Date.now;
    this.#fetch = opts.fetch ?? ((input, init) => globalThis.fetch(input, init));
    this.#log = opts.log;
    this.#upstream = { request: (url, init) => this.#request(url, init) };
  }

  /** The shared cache's key of a frame's grid, by the source's grid version. */
  gridKey(ms: number): string {
    return `${this.source.name}:grid:v${String(this.source.gridVersion)}:${this.source.stamp(ms)}`;
  }

  #key(what: string): string {
    return `${this.source.name}:${what}`;
  }

  /** The frames of the last [RadarSource.historyMs], oldest first, epoch ms. */
  async frames(): Promise<number[]> {
    const now = this.#now();
    const mine = this.#listing;
    if (mine !== undefined && now - mine.at < LISTING_TTL_S * 1000) return mine.frames;
    this.#listingInFlight ??= this.#list().finally(() => {
      this.#listingInFlight = undefined;
    });
    return this.#listingInFlight;
  }

  async #list(): Promise<number[]> {
    const now = this.#now();
    const listingKey = this.#key('frames');
    const failKey = this.#key('frames:fail');
    const shared = await this.#counters.get<{ at: number; frames: number[] }>(listingKey);
    if (shared !== undefined && now - shared.at < LISTING_TTL_S * 1000) {
      this.#listing = shared;
      return shared.frames;
    }
    if ((await this.#counters.get<boolean>(failKey)) === true) {
      throw new RadarUpstreamError('listing failed a moment ago');
    }
    const from = now - this.source.historyMs;
    let listed: number[];
    try {
      listed = await this.source.list(this.#upstream, from, now);
    } catch (err) {
      await this.#counters.set(failKey, true, FAIL_TTL_S);
      throw err instanceof RadarUpstreamError
        ? err
        : new RadarUpstreamError(`listing not readable: ${err instanceof Error ? err.message : String(err)}`);
    }
    const frames = [...new Set(listed.filter((t) => t >= from && t <= now))].sort((a, b) => a - b);
    const listing = { at: now, frames };
    this.#listing = listing;
    await this.#counters.set(listingKey, listing, LISTING_TTL_S);
    return frames;
  }

  /** The PNG of the area `box` at frame `time`, `width` x `height`. */
  async image(time: number, box: MercatorBox, width: number, height: number): Promise<Buffer> {
    const key = `${String(time)}:${box.map((v) => v.toFixed(1)).join(',')}:${String(width)}x${String(height)}`;
    const cached = this.#images.get(key);
    if (cached !== undefined) {
      // Most recently used last.
      this.#images.delete(key);
      this.#images.set(key, cached);
      return cached;
    }
    const grid = await this.grid(time);
    const projection = this.source.projection(grid.proj);
    const png = await encodeClassPng(width, height, classesOfArea(grid, projection, box, width, height));
    // Two requests for the same image may have drawn it both; count it once.
    const earlier = this.#images.get(key);
    if (earlier !== undefined) this.#imageBytes -= earlier.length;
    this.#images.set(key, png);
    this.#imageBytes += png.length;
    for (const [k, v] of this.#images) {
      if (this.#imageBytes <= IMAGE_CACHE_BYTES) break;
      this.#images.delete(k);
      this.#imageBytes -= v.length;
    }
    return png;
  }

  /** The class grid of frame `time`: memory, the shared cache, or the publisher once. */
  async grid(time: number): Promise<ClassGrid<P>> {
    const held = this.#grids.get(time);
    if (held !== undefined) {
      this.#grids.delete(time);
      this.#grids.set(time, held);
      return held;
    }
    let pending = this.#inFlight.get(time);
    if (pending === undefined) {
      pending = this.#load(time).finally(() => this.#inFlight.delete(time));
      this.#inFlight.set(time, pending);
    }
    const grid = await pending;
    this.#grids.set(time, grid);
    while (this.#grids.size > GRIDS_IN_MEMORY) {
      const oldest = this.#grids.keys().next().value;
      if (oldest === undefined) break;
      this.#grids.delete(oldest);
    }
    return grid;
  }

  async #readShared(time: number): Promise<ClassGrid<P> | undefined> {
    try {
      const bytes = await this.#counters.get<Uint8Array>(this.gridKey(time));
      return bytes === undefined
        ? undefined
        : await parseGrid<P>(Buffer.from(bytes), this.source.gridFormat);
    } catch {
      return undefined;
    }
  }

  async #load(time: number): Promise<ClassGrid<P>> {
    const shared = await this.#readShared(time);
    if (shared !== undefined) return shared;
    const failKey = this.#key(`fail:${String(time)}`);
    if ((await this.#counters.get<boolean>(failKey)) === true) {
      throw new RadarUpstreamError('frame failed a moment ago');
    }
    // One worker fetches; the others wait for its entry, and fetch
    // themselves only if it never comes, or cannot be shared.
    const unsharedKey = this.#key(`unshared:${String(time)}`);
    const unshared = async () => (await this.#counters.get<boolean>(unsharedKey)) === true;
    const lock = (await unshared())
      ? 1
      : await this.#counters.incr(this.#key(`lock:${String(time)}`), 1, { ttlIfNew: LOCK_TTL_S });
    if (lock > 1) {
      const deadline = Date.now() + LOCK_WAIT_MS;
      while (Date.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, LOCK_POLL_MS));
        const theirs = await this.#readShared(time);
        if (theirs !== undefined) return theirs;
        if ((await this.#counters.get<boolean>(failKey)) === true) {
          throw new RadarUpstreamError('frame failed on another worker');
        }
        if (await unshared()) break;
      }
    }
    let grid: ClassGrid<P>;
    try {
      grid = await this.#bounded(() => this.#fetchGrid(time));
    } catch (err) {
      // Not asked again for a while, by any worker.
      await this.#counters.set(failKey, true, FAIL_TTL_S);
      throw err;
    }
    await this.#share(time, grid);
    return grid;
  }

  /** Runs `job` once fewer than [MAX_FETCHES] are running in this worker. */
  async #bounded<T>(job: () => Promise<T>): Promise<T> {
    if (this.#fetching >= MAX_FETCHES) {
      // The slot is handed over by the job that ends, never taken twice.
      await new Promise<void>((resolve) => this.#queue.push(resolve));
    } else {
      this.#fetching += 1;
    }
    try {
      return await job();
    } finally {
      const next = this.#queue.shift();
      if (next === undefined) this.#fetching -= 1;
      else next();
    }
  }

  async #fetchGrid(time: number): Promise<ClassGrid<P>> {
    const started = this.#now();
    let res: Response;
    try {
      res = await this.source.fetchFrame(this.#upstream, time);
    } catch (err) {
      throw err instanceof RadarUpstreamError
        ? err
        : new RadarUpstreamError(`frame not found: ${err instanceof Error ? err.message : String(err)}`);
    }
    if (!res.ok) throw new RadarUpstreamError(`frame answered ${String(res.status)}`);
    const body = new Uint8Array(await res.arrayBuffer());
    if (body.length === 0 || body.length > this.source.maxFileBytes) {
      throw new RadarUpstreamError('frame of unexpected size');
    }
    let grid: ClassGrid<P>;
    try {
      grid = await this.source.decode(body);
    } catch (err) {
      throw new RadarUpstreamError(`frame not readable: ${err instanceof Error ? err.message : String(err)}`);
    }
    this.#log?.info(
      { frame: this.source.stamp(time), bytes: body.length, ms: this.#now() - started },
      `${this.source.name} frame fetched`,
    );
    return grid;
  }

  async #share(time: number, grid: ClassGrid<P>): Promise<void> {
    try {
      const bytes = await serialiseGrid(grid, this.source.gridFormat);
      if (bytes.length > this.#maxSharedBytes) {
        // The cache would refuse it: this worker keeps it in memory, the
        // others fetch their own.
        this.#log?.warn(
          { frame: this.source.stamp(time), bytes: bytes.length },
          `${this.source.name} grid too large to share`,
        );
        await this.#markUnshared(time);
        return;
      }
      await this.#counters.set(this.gridKey(time), new Uint8Array(bytes), this.source.keepMs / 1000);
    } catch (err) {
      this.#log?.warn({ err: String(err) }, `${this.source.name} grid not shared`);
      await this.#markUnshared(time);
    }
  }

  /** Tells the other workers not to wait for this frame's grid. */
  async #markUnshared(time: number): Promise<void> {
    try {
      await this.#counters.set(this.#key(`unshared:${String(time)}`), true, this.source.keepMs / 1000);
    } catch {
      // They wait out the lock instead.
    }
  }

  async #request(
    url: string,
    init: Parameters<RadarUpstream['request']>[1],
  ): Promise<Response> {
    try {
      return await this.#fetch(url, {
        method: init.method ?? 'GET',
        headers: { ...init.headers, 'user-agent': this.#userAgent },
        ...(init.body === undefined ? {} : { body: init.body }),
        ...(init.redirect === undefined ? {} : { redirect: init.redirect }),
        signal: AbortSignal.timeout(init.timeoutMs),
      });
    } catch (err) {
      throw new RadarUpstreamError(`${this.source.name} unreachable: ${err instanceof Error ? err.name : 'error'}`);
    }
  }
}
