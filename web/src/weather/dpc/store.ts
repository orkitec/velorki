// SPDX-License-Identifier: AGPL-3.0-only
import { SITE_URL } from '@/site/config';
import { mercatorOf, type MercatorBox } from '../radar/render';
import {
  RadarStore,
  RadarUpstreamError,
  type RadarSource,
  type RadarStoreOptions,
  type RadarUpstream,
} from '../radar/store';
import { DPC_GRID_FORMAT, DPC_GRID_VERSION, decodeDpcTiff } from './grid';
import { Tmerc, type TmercParams } from './tmerc';

/**
 * Italy's national radar: the SRI (surface rainfall intensity, mm an hour,
 * radars adjusted by rain gauges) of the Dipartimento della Protezione
 * Civile's Radar-DPC platform, fetched lazily (see `RadarStore` for the
 * caching) through its REST API (https://dpc-radar.readthedocs.io/it/latest/api.html):
 *
 * - The frames: `GET /findLastProductByType?type=SRI` names the newest; the
 *   platform keeps fourteen days, so every five minutes back from it are
 *   frames too. The API lists nothing older than the newest.
 * - A frame: `POST /downloadProduct` with the product and its time answers
 *   a pre-signed link to the GeoTIFF in the platform's S3 bucket (five
 *   minutes valid). The link is followed only when it names the file of
 *   that product and time, in a DPC radar bucket on S3 in eu-south-1.
 *
 * The API asks every request to carry an `origin` (its docs: "è necessario
 * includere il parametro origin in tutte le richieste"; as of 2026-10 it
 * answers without one too); the relay sends its own site's.
 *
 * The data is CC BY-SA 4.0 ("a condizione di citare la fonte Radar-DPC e di
 * rilasciare eventuali opere derivate con la stessa licenza"): the images
 * drawn from it are drawn from it alone, never composited with another
 * source, and carry [DPC_ATTRIBUTION].
 */

/** The platform's REST API. */
export const DPC_API = 'https://radar-api.protezionecivile.it';

/** The `origin` the API is sent: the site's (`https://velorki.com`, a fork's own). */
export const DPC_ORIGIN = new URL(SITE_URL).origin;

/** The product: surface rainfall intensity. */
export const DPC_PRODUCT = 'SRI';

/** The credit the app shows with the layer, as the DPC asks and under the licence. */
export const DPC_ATTRIBUTION =
  'Radar: Radar-DPC, Dipartimento della Protezione Civile (CC BY-SA 4.0)';

/** How far back the frames are offered. */
export const DPC_HISTORY_MS = 2 * 60 * 60 * 1000;
/** How long a frame's grid stays in the shared cache. */
export const DPC_KEEP_MS = 150 * 60 * 1000;
/** The product's step. */
export const DPC_STEP_MS = 5 * 60 * 1000;

const API_TIMEOUT_MS = 10_000;
const FETCH_TIMEOUT_MS = 30_000;
/** A frame is some 400 KB; refuse anything absurd. */
const MAX_TIFF_BYTES = 16 * 1024 * 1024;
/** The API's answers are a few hundred bytes (a link of some 2 KB). */
const MAX_API_BYTES = 64 * 1024;

/**
 * The hosts a link to a frame may name: a DPC radar bucket in S3's
 * eu-south-1, virtual-hosted (`s3-prod-dpc-radar.s3.eu-south-1.amazonaws.com`
 * as of 2026-10; `dpc-radar.` in the API's docs).
 */
const FRAME_HOST_RE = /^(?:[a-z0-9-]+-)?dpc-radar\.s3\.eu-south-1\.amazonaws\.com$/;

/**
 * The box around the product's grid (1200 x 1400 cells of a kilometre,
 * x -600 to 600 km, y -750 to 650 km of 42° N 12.5° E): 4.52° to 20.48° E,
 * 35.07° to 47.85° N, its corners and edges as projected back, rounded
 * outwards. In Web Mercator: the app's coverage box of the source, and what
 * an image request has to meet.
 */
const [DOMAIN_WEST, DOMAIN_SOUTH] = mercatorOf(4.5, 35);
const [DOMAIN_EAST, DOMAIN_NORTH] = mercatorOf(20.5, 47.9);
export const DPC_DOMAIN: MercatorBox = [DOMAIN_WEST, DOMAIN_SOUTH, DOMAIN_EAST, DOMAIN_NORTH];

function pad(n: number): string {
  return String(n).padStart(2, '0');
}

/** `DD-MM-YYYY-HH-MM` of an epoch ms, UTC: the stamp the bucket's names carry. */
export function dpcStamp(ms: number): string {
  const d = new Date(ms);
  return (
    `${pad(d.getUTCDate())}-${pad(d.getUTCMonth() + 1)}-${String(d.getUTCFullYear())}` +
    `-${pad(d.getUTCHours())}-${pad(d.getUTCMinutes())}`
  );
}

/** The bucket key of the SRI at `ms`. */
export function dpcKey(ms: number): string {
  return `${DPC_PRODUCT}/${dpcStamp(ms)}.tif`;
}

/** The headers every request to the API carries besides the user agent. */
const API_HEADERS = { origin: DPC_ORIGIN, accept: 'application/json' };

/** A small JSON answer of the API, or an error. */
async function apiJson(res: Response, what: string): Promise<unknown> {
  if (!res.ok) throw new RadarUpstreamError(`${what} answered ${String(res.status)}`);
  const text = await res.text();
  if (text.length > MAX_API_BYTES) throw new RadarUpstreamError(`${what} too long`);
  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new RadarUpstreamError(`${what} not JSON`);
  }
}

/**
 * The newest SRI time `findLastProductByType` names, epoch ms, or an error:
 * `{"total": 1, "lastProducts": [{"productType": "SRI", "time": 1791859200000, "period": "PT5M"}]}`.
 */
export function parseLastProduct(body: unknown): number {
  const products = (body as { lastProducts?: unknown } | null)?.lastProducts;
  if (Array.isArray(products)) {
    for (const p of products as unknown[]) {
      const { productType, time } = (p ?? {}) as { productType?: unknown; time?: unknown };
      if (
        productType === DPC_PRODUCT &&
        typeof time === 'number' &&
        Number.isSafeInteger(time) &&
        time % DPC_STEP_MS === 0
      ) {
        return time;
      }
    }
  }
  throw new RadarUpstreamError('newest product not named');
}

/**
 * The link `downloadProduct` answers for the SRI at `time`, checked: it has
 * to name that product's file at that time (`key`, and the link's path) on
 * a DPC radar bucket ([FRAME_HOST_RE]) over https, with no credentials or
 * port of its own. Throws otherwise, and nothing is fetched.
 */
export function frameLink(body: unknown, time: number): string {
  const { key, url } = (body ?? {}) as { key?: unknown; url?: unknown };
  if (key !== dpcKey(time)) throw new RadarUpstreamError('link names another file');
  if (typeof url !== 'string') throw new RadarUpstreamError('no link');
  let link: URL;
  try {
    link = new URL(url);
  } catch {
    throw new RadarUpstreamError('link not a URL');
  }
  if (
    link.protocol !== 'https:' ||
    !FRAME_HOST_RE.test(link.hostname) ||
    link.port !== '' ||
    link.username !== '' ||
    link.password !== '' ||
    link.pathname !== `/${dpcKey(time)}`
  ) {
    throw new RadarUpstreamError('link not to the radar bucket');
  }
  return link.toString();
}

/** The DPC's SRI over Italy. */
export const DPC_SOURCE: RadarSource<TmercParams> = {
  name: 'dpc',
  label: 'DPC radar composite',
  attribution: DPC_ATTRIBUTION,
  stepMs: DPC_STEP_MS,
  historyMs: DPC_HISTORY_MS,
  keepMs: DPC_KEEP_MS,
  gridVersion: DPC_GRID_VERSION,
  gridFormat: DPC_GRID_FORMAT,
  maxFileBytes: MAX_TIFF_BYTES,
  domain: DPC_DOMAIN,
  stamp: dpcStamp,
  async list(upstream: RadarUpstream, from: number, now: number): Promise<number[]> {
    const res = await upstream.request(
      `${DPC_API}/findLastProductByType?type=${DPC_PRODUCT}`,
      { timeoutMs: API_TIMEOUT_MS, headers: API_HEADERS, redirect: 'error' },
    );
    const newest = Math.min(parseLastProduct(await apiJson(res, 'newest product')), now);
    const out: number[] = [];
    for (let t = newest - (newest % DPC_STEP_MS); t >= from; t -= DPC_STEP_MS) out.push(t);
    return out;
  },
  async fetchFrame(upstream: RadarUpstream, time: number): Promise<Response> {
    const res = await upstream.request(`${DPC_API}/downloadProduct`, {
      timeoutMs: API_TIMEOUT_MS,
      method: 'POST',
      headers: { ...API_HEADERS, 'content-type': 'application/json' },
      body: JSON.stringify({ productType: DPC_PRODUCT, productDate: time }),
      redirect: 'error',
    });
    const link = frameLink(await apiJson(res, 'download link'), time);
    return upstream.request(link, { timeoutMs: FETCH_TIMEOUT_MS, redirect: 'error' });
  },
  decode: (bytes) => decodeDpcTiff(bytes),
  projection: (proj) => new Tmerc(proj),
};

/** The DPC's SRI frames, grids and images. */
export class DpcStore extends RadarStore<TmercParams> {
  constructor(opts: RadarStoreOptions) {
    super(DPC_SOURCE, opts);
  }
}
