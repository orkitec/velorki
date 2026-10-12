// SPDX-License-Identifier: AGPL-3.0-only

/**
 * The rain classes the OPERA radar is drawn in: the DWD radar's legend, so
 * the phone reads an OPERA image exactly as it reads the DWD's
 * (`RainPalette.dwd`) and the two look the same side by side.
 *
 * The one source of truth is the app: `dwdRadarLegend` and
 * `dwdRadarClassFloors` in `app/lib/features/map/data/rain_legend.dart`.
 * These are copies, and `test/opera.test.ts` reads that file and fails when
 * they drift apart.
 */

/** The lower bound of each class, mm an hour, the lightest first. */
export const DWD_CLASS_FLOORS: readonly number[] = [
  0.1, 0.2, 0.4, 1, 2, 3, 5, 7.5, 10, 15, 30, 45, 75, 100, 150,
];

/** The colour of each class, 0xRRGGBB, drawn fully opaque. */
export const DWD_CLASS_COLOURS: readonly number[] = [
  0x33ffff, 0x1acc9a, 0x019934, 0x4db31b, 0x99cc01, 0xcce601, 0xffff01, 0xffc401, 0xff8901,
  0xff4501, 0xfe0000, 0xe5004c, 0xcc0098, 0x6600cb, 0x0000fe,
];

/**
 * "No data", as the DWD draws it: `#7E7E7E` at alpha 77. The phone reads a
 * pixel near `#7D7D7D` as no data (`dwdRadarLegend.noData`) and lets the
 * sources after this one draw there.
 */
export const NO_DATA_RGB = 0x7e7e7e;
export const NO_DATA_ALPHA = 77;

/** A cell of the class grid: dry (or no echo). */
export const CLASS_DRY = 0;
/** A cell of the class grid: outside every radar's reach. */
export const CLASS_NO_DATA = 255;
// Classes 1..15 are DWD_CLASS_FLOORS[k - 1].

/** The rain rate, mm an hour, of `dbz` by Marshall-Palmer, Z = 200 R^1.6. */
export function marshallPalmerRate(dbz: number): number {
  return Math.pow(Math.pow(10, dbz / 10) / 200, 1 / 1.6);
}

/**
 * The reflectivity floor of each class, dBZ: the inverse of
 * [marshallPalmerRate] at each floor, so a cell is classed by comparisons
 * alone.
 */
export const DWD_CLASS_DBZ_FLOORS: readonly number[] = DWD_CLASS_FLOORS.map(
  (r) => 10 * Math.log10(200 * Math.pow(r, 1.6)),
);

/** The class grid's value of a reflectivity: 0 dry, 1..15 the class. */
export function classOfDbz(dbz: number): number {
  let k = CLASS_DRY;
  for (let i = 0; i < DWD_CLASS_DBZ_FLOORS.length; i += 1) {
    if (dbz >= (DWD_CLASS_DBZ_FLOORS[i] ?? Infinity)) k = i + 1;
    else break;
  }
  return k;
}
