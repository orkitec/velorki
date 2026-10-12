// SPDX-License-Identifier: AGPL-3.0-only
import { promisify } from 'node:util';
import { crc32, deflate } from 'node:zlib';
import { CLASS_NO_DATA, DWD_CLASS_COLOURS, NO_DATA_ALPHA, NO_DATA_RGB } from './classes';
import type { ClassGrid } from './grid';
import { Laea } from './laea';

const deflateAsync = promisify(deflate);

/** Half the Web Mercator world, metres. */
export const MERCATOR_HALF = 20037508.342789244;
const EARTH_RADIUS = 6378137;

/** A Web Mercator box: west, south, east, north in metres (EPSG:3857). */
export type MercatorBox = readonly [number, number, number, number];

/** Web Mercator `x` of a longitude and `y` of a latitude, degrees. */
export function mercatorOf(lon: number, lat: number): [number, number] {
  const phi = (Math.max(-85.051129, Math.min(85.051129, lat)) * Math.PI) / 180;
  return [(lon * MERCATOR_HALF) / 180, Math.log(Math.tan(Math.PI / 4 + phi / 2)) * EARTH_RADIUS];
}

/**
 * The box around the composite's grid, 39.5° W to 57.8° E and 31.7° to
 * 73.9° N (its corners and edges, worked out from the grid of 2026-10-12),
 * in Web Mercator: the app's coverage box of the source, and what an image
 * request has to meet.
 */
const [DOMAIN_WEST, DOMAIN_SOUTH] = mercatorOf(-39.5, 31.7);
const [DOMAIN_EAST, DOMAIN_NORTH] = mercatorOf(57.8, 73.9);
export const OPERA_DOMAIN: MercatorBox = [DOMAIN_WEST, DOMAIN_SOUTH, DOMAIN_EAST, DOMAIN_NORTH];

/**
 * The palette index of each pixel: 0 transparent (dry, or outside the
 * composite), 1..15 the DWD classes, [PALETTE_NO_DATA] no data.
 */
export const PALETTE_NO_DATA = DWD_CLASS_COLOURS.length + 1;

/** How fine the samples under one image pixel may be, at most, a side. */
const MAX_SUPERSAMPLE = 3;

/**
 * Which class lies under each pixel of a `width` x `height` image of `box`:
 * each pixel's middle (and, where a pixel spans more than a cell and a half
 * on the ground, a few points across it) projected into the composite's
 * grid, the heaviest rain among them kept, so rain a cell wide still shows
 * zoomed out. A pixel with no sample on the grid is transparent; one whose
 * samples are all no data is no data.
 */
export function classesOfArea(
  grid: ClassGrid,
  box: MercatorBox,
  width: number,
  height: number,
): Uint8Array {
  const [west, south, east, north] = box;
  const out = new Uint8Array(width * height);
  const laea = new Laea(grid.proj);
  const pxX = (east - west) / width;
  const pxY = (north - south) / height;
  const midLat = latOf((north + south) / 2);
  const groundPx = Math.max(pxX, pxY) * Math.cos((midLat * Math.PI) / 180);
  const cell = Math.min(grid.dx, grid.dy);
  const ss = Math.max(1, Math.min(MAX_SUPERSAMPLE, Math.ceil(groundPx / (1.5 * cell))));

  // The longitude depends on the column alone, the latitude on the row.
  const cols = width * ss;
  const sinL = new Float64Array(cols);
  const cosL = new Float64Array(cols);
  for (let c = 0; c < cols; c += 1) {
    const x = west + ((c + 0.5) / ss) * pxX;
    const dl = laea.dLon((x / MERCATOR_HALF) * 180);
    sinL[c] = Math.sin(dl);
    cosL[c] = Math.cos(dl);
  }
  const rows = height * ss;
  const sinB = new Float64Array(rows);
  const cosB = new Float64Array(rows);
  for (let r = 0; r < rows; r += 1) {
    const y = north - ((r + 0.5) / ss) * pxY;
    const beta = laea.beta(latOf(y));
    sinB[r] = beta.sin;
    cosB[r] = beta.cos;
  }

  const { x0, y0, dx, dy, width: gw, height: gh, cells } = grid;
  for (let j = 0; j < height; j += 1) {
    for (let i = 0; i < width; i += 1) {
      // -1 nothing on the grid yet, else the best: rain over dry over no data.
      let best = -1;
      for (let sr = 0; sr < ss; sr += 1) {
        const r = j * ss + sr;
        for (let sc = 0; sc < ss; sc += 1) {
          const c = i * ss + sc;
          const p = laea.forwardParts(sinB[r] ?? 0, cosB[r] ?? 0, sinL[c] ?? 0, cosL[c] ?? 1);
          if (p === null) continue;
          const col = Math.floor((p.x - x0) / dx);
          const row = Math.floor((y0 - p.y) / dy);
          if (col < 0 || row < 0 || col >= gw || row >= gh) continue;
          const v = cells[row * gw + col] ?? CLASS_NO_DATA;
          const rank = v === CLASS_NO_DATA ? 0 : v + 1;
          if (rank > best) best = rank;
        }
      }
      out[j * width + i] = best <= 0 ? (best === 0 ? PALETTE_NO_DATA : 0) : best - 1;
    }
  }
  return out;
}

/** The latitude, degrees, of Web Mercator `y`. */
function latOf(y: number): number {
  return ((2 * Math.atan(Math.exp(y / EARTH_RADIUS)) - Math.PI / 2) * 180) / Math.PI;
}

function chunk(type: string, data: Uint8Array): Buffer {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(data, crc32(Buffer.from(type, 'ascii'))) >>> 0, 0);
  return Buffer.concat([head, data, crc]);
}

/**
 * `indices` (one palette index a pixel, see [classesOfArea]) as an indexed
 * PNG: the DWD classes' colours fully opaque, no data its grey at the DWD's
 * alpha, index 0 transparent.
 */
export async function encodeClassPng(
  width: number,
  height: number,
  indices: Uint8Array,
): Promise<Buffer> {
  const colours = [0x000000, ...DWD_CLASS_COLOURS, NO_DATA_RGB];
  const plte = Buffer.alloc(colours.length * 3);
  colours.forEach((c, i) => {
    plte[i * 3] = (c >> 16) & 0xff;
    plte[i * 3 + 1] = (c >> 8) & 0xff;
    plte[i * 3 + 2] = c & 0xff;
  });
  const trns = Buffer.alloc(colours.length, 255);
  trns[0] = 0;
  trns[PALETTE_NO_DATA] = NO_DATA_ALPHA;

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 3; // indexed colour
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  const raw = Buffer.alloc((width + 1) * height);
  for (let y = 0; y < height; y += 1) {
    raw[y * (width + 1)] = 0;
    raw.set(indices.subarray(y * width, (y + 1) * width), y * (width + 1) + 1);
  }
  const idat = await deflateAsync(raw, { level: 6 });
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('PLTE', plte),
    chunk('tRNS', trns),
    chunk('IDAT', idat),
    chunk('IEND', new Uint8Array(0)),
  ]);
}
