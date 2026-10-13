// SPDX-License-Identifier: AGPL-3.0-only
import { mercatorOf, type MercatorBox } from '../radar/render';
import {
  RadarStore,
  RadarUpstreamError,
  type RadarSource,
  type RadarStoreOptions,
  type RadarUpstream,
} from '../radar/store';
import { GRID_VERSION, OPERA_GRID_FORMAT, decodeOperaTiff } from './grid';
import { Laea, type LaeaParams } from './laea';

/**
 * The OPERA radar composite, fetched lazily from EUMETNET's open bucket
 * (see `RadarStore` for the caching): the frames are the bucket's listing,
 * one S3 ListObjectsV2 per UTC hour the last two hours span; a frame's grid
 * (3800 x 4400 cells, some 17 MB in memory, some 350 KB deflated) is the
 * reflectivity composite's GeoTIFF of its time.
 */

/** The bucket, anonymous and read-only. */
export const OPERA_BUCKET = 'https://s3.waw3-1.cloudferro.com/openradar-24h';

/** The credit the app shows with the layer. */
export const OPERA_ATTRIBUTION = 'Radar: EUMETNET OPERA (CC BY 4.0)';

/** How far back the frames are offered. */
export const OPERA_HISTORY_MS = 2 * 60 * 60 * 1000;
/** How long a frame's grid stays in the shared cache. */
export const OPERA_KEEP_MS = 150 * 60 * 1000;
/** The composite's step. */
export const OPERA_STEP_MS = 5 * 60 * 1000;

const FETCH_TIMEOUT_MS = 30_000;
const LIST_TIMEOUT_MS = 10_000;
/** A composite file is some 3 MB; refuse anything absurd. */
const MAX_TIFF_BYTES = 32 * 1024 * 1024;

/**
 * The box around the composite's grid, 39.5° W to 57.8° E and 31.7° to
 * 73.9° N (its corners and edges, worked out from the grid of 2026-10-12),
 * in Web Mercator: the app's coverage box of the source, and what an image
 * request has to meet.
 */
const [DOMAIN_WEST, DOMAIN_SOUTH] = mercatorOf(-39.5, 31.7);
const [DOMAIN_EAST, DOMAIN_NORTH] = mercatorOf(57.8, 73.9);
export const OPERA_DOMAIN: MercatorBox = [DOMAIN_WEST, DOMAIN_SOUTH, DOMAIN_EAST, DOMAIN_NORTH];

function pad(n: number, width = 2): string {
  return String(n).padStart(width, '0');
}

/** `YYYYMMDDTHHMM` of an epoch ms, UTC: the stamp the bucket's names carry. */
export function operaStamp(ms: number): string {
  const d = new Date(ms);
  return (
    `${String(d.getUTCFullYear())}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}` +
    `T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}`
  );
}

function dayPath(ms: number): string {
  const d = new Date(ms);
  return `${String(d.getUTCFullYear())}/${pad(d.getUTCMonth() + 1)}/${pad(d.getUTCDate())}`;
}

/** The shared cache's key of a frame's grid, by [GRID_VERSION]. */
export function operaGridKey(ms: number): string {
  return `opera:grid:v${String(GRID_VERSION)}:${operaStamp(ms)}`;
}

/** The bucket key of the reflectivity composite at `ms`. */
export function operaKey(ms: number): string {
  return `${dayPath(ms)}/OPERA/COMP/OPERA@${operaStamp(ms)}@0@DBZH.tiff`;
}

const KEY_RE = /<Key>(\d{4}\/\d{2}\/\d{2}\/OPERA\/COMP\/OPERA@(\d{8}T\d{4})@0@DBZH\.tiff)<\/Key>/g;

/** The frame times, epoch ms, an S3 listing names. */
export function parseListing(xml: string): number[] {
  const out: number[] = [];
  for (const m of xml.matchAll(KEY_RE)) {
    const s = m[2] ?? '';
    const ms = Date.UTC(
      Number(s.slice(0, 4)),
      Number(s.slice(4, 6)) - 1,
      Number(s.slice(6, 8)),
      Number(s.slice(9, 11)),
      Number(s.slice(11, 13)),
    );
    if (Number.isFinite(ms)) out.push(ms);
  }
  return out;
}

/** EUMETNET OPERA's maximum reflectivity composite over Europe. */
export const OPERA_SOURCE: RadarSource<LaeaParams> = {
  name: 'opera',
  label: 'OPERA composite',
  attribution: OPERA_ATTRIBUTION,
  stepMs: OPERA_STEP_MS,
  historyMs: OPERA_HISTORY_MS,
  keepMs: OPERA_KEEP_MS,
  gridVersion: GRID_VERSION,
  gridFormat: OPERA_GRID_FORMAT,
  maxFileBytes: MAX_TIFF_BYTES,
  domain: OPERA_DOMAIN,
  stamp: operaStamp,
  async list(upstream: RadarUpstream, from: number, now: number): Promise<number[]> {
    const found: number[] = [];
    for (let hour = from - (from % 3_600_000); hour <= now; hour += 3_600_000) {
      const prefix = `${dayPath(hour)}/OPERA/COMP/OPERA@${operaStamp(hour).slice(0, 11)}`;
      const url = `${OPERA_BUCKET}?list-type=2&prefix=${encodeURIComponent(prefix)}`;
      const res = await upstream.request(url, { timeoutMs: LIST_TIMEOUT_MS });
      if (!res.ok) throw new RadarUpstreamError(`listing answered ${String(res.status)}`);
      found.push(...parseListing(await res.text()));
    }
    return found;
  },
  fetchFrame: (upstream, time) =>
    upstream.request(`${OPERA_BUCKET}/${operaKey(time)}`, { timeoutMs: FETCH_TIMEOUT_MS }),
  decode: (bytes) => decodeOperaTiff(bytes),
  projection: (proj) => new Laea(proj),
};

/** The OPERA composite's frames, grids and images. */
export class OperaStore extends RadarStore<LaeaParams> {
  constructor(opts: RadarStoreOptions) {
    super(OPERA_SOURCE, opts);
  }
}
