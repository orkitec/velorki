// SPDX-License-Identifier: AGPL-3.0-only
import { promisify } from 'node:util';
import { deflate, inflate } from 'node:zlib';
import { CLASS_DRY, CLASS_NO_DATA } from './classes';

const deflateAsync = promisify(deflate);
const inflateAsync = promisify(inflate);

/**
 * One radar frame as the relay keeps it: the composite's grid, one byte a
 * cell, already in the DWD radar's classes (`classes.ts`): 0 dry or no echo,
 * 1..15 a class, 255 no data (beyond every radar's reach). `proj` names the
 * grid's projection in the source's own terms (`RadarSource.projection`
 * turns it into one that draws).
 */
export interface ClassGrid<P> {
  width: number;
  height: number;
  /** Projected x of the west edge of column 0, metres. */
  x0: number;
  /** Projected y of the north edge of row 0, metres. */
  y0: number;
  /** Cell width and height, metres (both positive). */
  dx: number;
  dy: number;
  proj: P;
  cells: Uint8Array;
}

/**
 * A patch of rain smaller than this many cells (8-connected) is speckle:
 * single cells and pairs scattered by clutter and noise all over the
 * composite. Some 2 600 patches, 0.5 % of the rain cells, in an OPERA frame.
 */
export const MIN_ECHO_CELLS = 4;

/** The class from which a cell counts as heavy: 5 mm an hour, about 34 dBZ. */
export const HEAVY_CLASS = 7;

/**
 * A patch of rain more than this share of whose cells are heavy has no
 * light rain around it: real rain thins out over kilometres, while
 * interference spokes and fixed clutter (wind farms, ships, masts) are
 * strong echoes with a hard edge. In four OPERA frames of 2026-10-12 every
 * patch of real rain of 50 cells or more stayed under 0.35 (Irish showers up
 * to 60 dBZ: 0.34), the spokes over Czechia and Slovakia were 0.57 to 0.99.
 */
export const MAX_HEAVY_SHARE = 0.5;

/**
 * Drops clutter from a class grid in place, as dry: patches of rain
 * (8-connected cells of any class) under [MIN_ECHO_CELLS] cells, and those
 * of which more than [MAX_HEAVY_SHARE] is heavy ([HEAVY_CLASS] and up).
 *
 * The OPERA composite's quality index (the file's second sample) does not
 * tell them apart: 95 % of the rain cells carry 0 there, the real rain over
 * Ireland and Romania as much as the spokes.
 */
export function dropClutter(cells: Uint8Array, width: number, height: number): void {
  const isRain = (v: number) => v !== CLASS_DRY && v !== CLASS_NO_DATA;
  let rain = 0;
  for (const v of cells) if (isRain(v)) rain += 1;
  if (rain === 0) return;
  const seen = new Uint8Array(cells.length);
  // One patch's cells, in the order found: the queue is the patch.
  const queue = new Int32Array(rain);
  for (let start = 0; start < cells.length; start += 1) {
    if (seen[start] === 1 || !isRain(cells[start] ?? 0)) continue;
    let head = 0;
    let tail = 0;
    let heavy = 0;
    queue[tail++] = start;
    seen[start] = 1;
    while (head < tail) {
      const i = queue[head++] ?? 0;
      if ((cells[i] ?? 0) >= HEAVY_CLASS) heavy += 1;
      const row = Math.floor(i / width);
      const col = i - row * width;
      for (let dr = -1; dr <= 1; dr += 1) {
        const r = row + dr;
        if (r < 0 || r >= height) continue;
        for (let dc = -1; dc <= 1; dc += 1) {
          const c = col + dc;
          if (c < 0 || c >= width || (dr === 0 && dc === 0)) continue;
          const j = r * width + c;
          if (seen[j] === 1 || !isRain(cells[j] ?? 0)) continue;
          seen[j] = 1;
          queue[tail++] = j;
        }
      }
    }
    if (tail < MIN_ECHO_CELLS || heavy / tail > MAX_HEAVY_SHARE) {
      for (let k = 0; k < tail; k += 1) cells[queue[k] ?? 0] = CLASS_DRY;
    }
  }
}

/** A number of a GeoTIFF's keys, or an error naming `what` and the key. */
export function geoKeyNumber(keys: Record<string, unknown>, name: string, what: string): number {
  const v = keys[name];
  if (typeof v !== 'number' || !Number.isFinite(v)) {
    throw new Error(`${what} GeoTIFF: ${name} missing`);
  }
  return v;
}

/** What heads a serialised grid of `format`: e.g. `velorki-opera-grid-2`. */
function magicOf(format: string): string {
  return `${format}\n`;
}

/** A grid as it is shared: a header line naming `format`, its shape as JSON, the cells deflated. */
export async function serialiseGrid<P>(grid: ClassGrid<P>, format: string): Promise<Buffer> {
  const { cells, ...shape } = grid;
  const head = Buffer.from(`${magicOf(format)}${JSON.stringify(shape)}\n`, 'utf8');
  const body = await deflateAsync(cells, { level: 6 });
  return Buffer.concat([head, body]);
}

/** A grid of `format` back from its bytes; throws on anything that is not one. */
export async function parseGrid<P>(file: Buffer, format: string): Promise<ClassGrid<P>> {
  const magic = magicOf(format);
  if (file.subarray(0, magic.length).toString('utf8') !== magic) {
    throw new Error(`not a ${format} file`);
  }
  const end = file.indexOf(0x0a, magic.length);
  if (end < 0) throw new Error(`${format} file: no header`);
  const shape = JSON.parse(file.subarray(magic.length, end).toString('utf8')) as Omit<
    ClassGrid<P>,
    'cells'
  >;
  const cells = new Uint8Array(await inflateAsync(file.subarray(end + 1)));
  if (cells.length !== shape.width * shape.height) throw new Error(`${format} file: truncated`);
  return { ...shape, cells };
}
