// SPDX-License-Identifier: AGPL-3.0-only
import { promisify } from 'node:util';
import { deflate, inflate } from 'node:zlib';
import { fromArrayBuffer } from 'geotiff';
import { CLASS_DRY, CLASS_NO_DATA, classOfDbz } from './classes';
import type { LaeaParams } from './laea';

const deflateAsync = promisify(deflate);
const inflateAsync = promisify(inflate);

/**
 * One OPERA frame as the relay keeps it: the composite's grid, one byte a
 * cell, already in the DWD radar's classes (`classes.ts`): 0 dry or no echo,
 * 1..15 a class, 255 no data (beyond every radar's reach). 3800 x 4400 cells
 * of a kilometre, some 17 MB in memory and a few hundred KB deflated on disk.
 */
export interface ClassGrid {
  width: number;
  height: number;
  /** Projected x of the west edge of column 0, metres. */
  x0: number;
  /** Projected y of the north edge of row 0, metres. */
  y0: number;
  /** Cell width and height, metres (both positive). */
  dx: number;
  dy: number;
  proj: LaeaParams;
  cells: Uint8Array;
}

/** GeoTIFF's code for Lambert Azimuthal Equal Area (`ProjCoordTransGeoKey`). */
const CT_LAMBERT_AZIM_EQUAL_AREA = 10;
/** GeoTIFF's code for metres (`ProjLinearUnitsGeoKey`). */
const LINEAR_METRE = 9001;
/** EPSG's WGS 84 ellipsoid, which the composite names by code. */
const ELLIPSOID_WGS84 = 7030;

/**
 * A patch of rain smaller than this many cells (8-connected) is speckle:
 * single cells and pairs scattered by clutter and noise all over the
 * composite. Some 2 600 patches, 0.5 % of the rain cells, in a frame.
 */
export const MIN_ECHO_CELLS = 4;

/** The class from which a cell counts as heavy: 5 mm an hour, about 34 dBZ. */
export const HEAVY_CLASS = 7;

/**
 * A patch of rain more than this share of whose cells are heavy has no
 * light rain around it: real rain thins out over kilometres, while
 * interference spokes and fixed clutter (wind farms, ships, masts) are
 * strong echoes with a hard edge. In four frames of 2026-10-12 every patch
 * of real rain of 50 cells or more stayed under 0.35 (Irish showers up to
 * 60 dBZ: 0.34), the spokes over Czechia and Slovakia were 0.57 to 0.99.
 */
export const MAX_HEAVY_SHARE = 0.5;

/**
 * Drops clutter from a class grid in place, as dry: patches of rain
 * (8-connected cells of any class) under [MIN_ECHO_CELLS] cells, and those
 * of which more than [MAX_HEAVY_SHARE] is heavy ([HEAVY_CLASS] and up).
 *
 * The composite's quality index (the file's second sample) does not tell
 * them apart: 95 % of the rain cells carry 0 there, the real rain over
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

/** Anything at or below this is the composite's fill value (-9 999 000). */
const FILL_BELOW = -9e6;

function num(keys: Record<string, unknown>, name: string): number {
  const v = keys[name];
  if (typeof v !== 'number' || !Number.isFinite(v)) {
    throw new Error(`OPERA GeoTIFF: ${name} missing`);
  }
  return v;
}

/**
 * The projection the file's GeoKeys name: Lambert Azimuthal Equal Area in
 * metres, its centre, false origin and ellipsoid. Anything else is refused,
 * since the drawing assumes it.
 */
export function laeaFromGeoKeys(keys: Record<string, unknown>): LaeaParams {
  if (keys.ProjCoordTransGeoKey !== CT_LAMBERT_AZIM_EQUAL_AREA) {
    throw new Error('OPERA GeoTIFF: not Lambert Azimuthal Equal Area');
  }
  if (keys.ProjLinearUnitsGeoKey !== undefined && keys.ProjLinearUnitsGeoKey !== LINEAR_METRE) {
    throw new Error('OPERA GeoTIFF: not in metres');
  }
  let a: number;
  let invFlattening: number;
  if (typeof keys.GeogSemiMajorAxisGeoKey === 'number') {
    a = num(keys, 'GeogSemiMajorAxisGeoKey');
    invFlattening = num(keys, 'GeogInvFlatteningGeoKey');
  } else if (keys.GeogEllipsoidGeoKey === ELLIPSOID_WGS84) {
    a = 6378137;
    invFlattening = 298.257223563;
  } else {
    throw new Error('OPERA GeoTIFF: unknown ellipsoid');
  }
  return {
    lat0: num(keys, 'ProjCenterLatGeoKey'),
    lon0: num(keys, 'ProjCenterLongGeoKey'),
    falseEasting: num(keys, 'ProjFalseEastingGeoKey'),
    falseNorthing: num(keys, 'ProjFalseNorthingGeoKey'),
    a,
    invFlattening,
  };
}

/**
 * The class grid of one `OPERA@…@DBZH.tiff`: the first sample of the full
 * resolution image (reflectivity, dBZ; the second is a quality index), NaN
 * ("undetect", no echo) and values under the lightest class dry, the fill
 * value no data.
 */
export async function decodeOperaTiff(
  bytes: Uint8Array,
  opts: { filter?: boolean } = {},
): Promise<ClassGrid> {
  const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  const tiff = await fromArrayBuffer(buffer as ArrayBuffer);
  const image = await tiff.getImage(0);
  const keys = image.getGeoKeys();
  if (keys === null) throw new Error('OPERA GeoTIFF: no GeoKeys');
  const proj = laeaFromGeoKeys(keys as Record<string, unknown>);
  const width = image.getWidth();
  const height = image.getHeight();
  const [x0, y0] = image.getOrigin();
  const [rx, ry] = image.getResolution();
  if (x0 === undefined || y0 === undefined || rx === undefined || ry === undefined) {
    throw new Error('OPERA GeoTIFF: no georeference');
  }
  const noData = image.getGDALNoData();
  const rasters = await image.readRasters({ samples: [0], interleave: false });
  const values = rasters[0];
  if (values === undefined || values.length !== width * height) {
    throw new Error('OPERA GeoTIFF: unexpected raster');
  }
  const cells = new Uint8Array(width * height);
  for (let i = 0; i < cells.length; i += 1) {
    const v = values[i] as number;
    if (Number.isNaN(v)) cells[i] = CLASS_DRY;
    else if (v <= FILL_BELOW || v === noData) cells[i] = CLASS_NO_DATA;
    else cells[i] = classOfDbz(v);
  }
  if (opts.filter ?? true) dropClutter(cells, width, height);
  return { width, height, x0, y0, dx: Math.abs(rx), dy: Math.abs(ry), proj, cells };
}

/**
 * The version of the grid files: bumped whenever what a grid holds changes
 * (2: [dropClutter]), so files of an older one are fetched and decoded anew
 * and pruned.
 */
export const GRID_VERSION = 2;

/** What heads a grid file: format, then the grid's shape as JSON. */
const MAGIC = `velorki-opera-grid-${String(GRID_VERSION)}\n`;

/** A grid as its file on disk: a header line and the cells deflated. */
export async function serialiseGrid(grid: ClassGrid): Promise<Buffer> {
  const { cells, ...shape } = grid;
  const head = Buffer.from(`${MAGIC}${JSON.stringify(shape)}\n`, 'utf8');
  const body = await deflateAsync(cells, { level: 6 });
  return Buffer.concat([head, body]);
}

/** A grid back from its file; throws on anything that is not one. */
export async function parseGrid(file: Buffer): Promise<ClassGrid> {
  if (file.subarray(0, MAGIC.length).toString('utf8') !== MAGIC) {
    throw new Error('not an OPERA grid file');
  }
  const end = file.indexOf(0x0a, MAGIC.length);
  if (end < 0) throw new Error('OPERA grid file: no header');
  const shape = JSON.parse(file.subarray(MAGIC.length, end).toString('utf8')) as Omit<
    ClassGrid,
    'cells'
  >;
  const cells = new Uint8Array(await inflateAsync(file.subarray(end + 1)));
  if (cells.length !== shape.width * shape.height) throw new Error('OPERA grid file: truncated');
  return { ...shape, cells };
}
