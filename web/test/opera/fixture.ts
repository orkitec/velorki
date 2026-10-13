// SPDX-License-Identifier: AGPL-3.0-only
import { writeArrayBuffer } from 'geotiff';

/**
 * A tiny OPERA composite built at test time, so no 3 MB frame is committed:
 * the real files' projection and GeoKeys (Lambert Azimuthal Equal Area, 55° N
 * 10° E, false origin 1 950 000 / -2 100 000, WGS 84 by EPSG ellipsoid code,
 * as `OPERA@…@DBZH.tiff` names them), 1 km cells, two float samples a pixel
 * (reflectivity, quality), NaN for no echo and -9 999 000 for no data.
 *
 * 20 x 20 cells whose north-west corner is at (1 379 500, -2 745 400): Paris
 * (48.85° N, 2.35° E, projected 1 389 004.5, -2 753 918.2) lies in the middle
 * of the cell in column 9, row 8, a shower: 40 dBZ there (11.5 mm an hour,
 * the DWD's 10-15 mm class), 20 dBZ in the 5 x 5 cells around it (0.65 mm,
 * the 0.4-1 mm class). Rows 15 and below are no data; the rest no echo but
 * for a 5 dBZ cell at column 2, row 2 (under the lightest class: dry), and
 * the clutter the decoding drops: a spoke of six 50 dBZ cells along row 12
 * from column 1, and a lone 20 dBZ cell at column 17, row 2.
 */
export const FIXTURE = {
  width: 20,
  height: 20,
  x0: 1_379_500,
  y0: -2_745_400,
  paris: { col: 9, row: 8, lat: 48.85, lon: 2.35, dbz: 40, rimDbz: 20 },
  noDataFromRow: 15,
  weak: { col: 2, row: 2, dbz: 5 },
  spoke: { row: 12, fromCol: 1, cells: 6, dbz: 50 },
  speck: { col: 17, row: 2, dbz: 20 },
} as const;

export function fixtureTiff(): Uint8Array {
  const { width, height, x0, y0, paris, noDataFromRow, weak, spoke, speck } = FIXTURE;
  const values = new Float32Array(width * height * 2);
  for (let row = 0; row < height; row += 1) {
    for (let col = 0; col < width; col += 1) {
      const i = (row * width + col) * 2;
      let v = Number.NaN;
      if (row >= noDataFromRow) v = -9_999_000;
      else if (col === paris.col && row === paris.row) v = paris.dbz;
      else if (Math.abs(col - paris.col) <= 2 && Math.abs(row - paris.row) <= 2) v = paris.rimDbz;
      else if (col === weak.col && row === weak.row) v = weak.dbz;
      else if (row === spoke.row && col >= spoke.fromCol && col < spoke.fromCol + spoke.cells)
        v = spoke.dbz;
      else if (col === speck.col && row === speck.row) v = speck.dbz;
      values[i] = v;
      values[i + 1] = row >= noDataFromRow ? -9_999_000 : 1;
    }
  }
  const buffer = writeArrayBuffer(values, {
    width,
    height,
    SamplesPerPixel: 2,
    BitsPerSample: [32, 32],
    SampleFormat: [3, 3],
    PlanarConfiguration: 1,
    PhotometricInterpretation: 1,
    ModelPixelScale: [1000, 1000, 0],
    ModelTiepoint: [0, 0, 0, x0, y0, 0],
    // The key directory as the real files carry it: model, raster type,
    // user-defined geographic and projected systems on the WGS 84 ellipsoid
    // (EPSG 7030), Lambert Azimuthal Equal Area (10) in metres (9001), the
    // centre and the false origin in the double parameters.
    GeoKeyDirectory: [
      1, 1, 0, 12,
      1024, 0, 1, 1,
      1025, 0, 1, 1,
      2048, 0, 1, 32767,
      2056, 0, 1, 7030,
      3072, 0, 1, 32767,
      3074, 0, 1, 32767,
      3075, 0, 1, 10,
      3076, 0, 1, 9001,
      3082, 34736, 1, 2,
      3083, 34736, 1, 3,
      3088, 34736, 1, 1,
      3089, 34736, 1, 0,
    ],
    GeoDoubleParams: [55, 10, 1_950_000, -2_100_000],
    // Named too, or the writer takes the image for a world map in degrees
    // and puts its own tie point in.
    ProjectedCSTypeGeoKey: 32767,
  });
  return new Uint8Array(buffer);
}
