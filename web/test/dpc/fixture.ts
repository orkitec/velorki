// SPDX-License-Identifier: AGPL-3.0-only
import { writeArrayBuffer } from 'geotiff';

/**
 * A tiny DPC SRI frame built at test time, so no frame is committed: the
 * real files' projection and GeoKeys (Transverse Mercator, natural origin
 * 42° N 12.5° E, no scale factor nor false origin named, on WGS 84 named by
 * EPSG 4326, as `SRI/DD-MM-YYYY-HH-MM.tif` names them), 1 km cells, one
 * float sample a pixel in mm an hour, 0 dry and -9999 for no data.
 *
 * 20 x 20 cells whose north-west corner is at (-9 500, -2 600): Rome's
 * meridian 41.9° N 12.5° E (projected 0, -11 107.2) lies in the middle of
 * the cell in column 9, row 8, a shower: 12 mm an hour there (the DWD's
 * 10-15 mm class), 0.7 mm in the 5 x 5 cells around it (the 0.4-1 mm
 * class). Rows 15 and below are no data; the rest dry but for a 0.05 mm
 * cell at column 2, row 2 (under the lightest class: dry), and what the
 * OPERA radar would drop as clutter and the DPC's keeps: six 40 mm cells
 * along row 12 from column 1, and a lone 0.7 mm cell at column 17, row 2.
 */
export const DPC_FIXTURE = {
  width: 20,
  height: 20,
  x0: -9_500,
  y0: -2_600,
  rome: { col: 9, row: 8, lat: 41.9, lon: 12.5, rate: 12, rimRate: 0.7 },
  noDataFromRow: 15,
  weak: { col: 2, row: 2, rate: 0.05 },
  band: { row: 12, fromCol: 1, cells: 6, rate: 40 },
  speck: { col: 17, row: 2, rate: 0.7 },
} as const;

export function dpcFixtureTiff(): Uint8Array {
  const { width, height, x0, y0, rome, noDataFromRow, weak, band, speck } = DPC_FIXTURE;
  const values = new Float32Array(width * height);
  for (let row = 0; row < height; row += 1) {
    for (let col = 0; col < width; col += 1) {
      let v = 0;
      if (row >= noDataFromRow) v = -9999;
      else if (col === rome.col && row === rome.row) v = rome.rate;
      else if (Math.abs(col - rome.col) <= 2 && Math.abs(row - rome.row) <= 2) v = rome.rimRate;
      else if (col === weak.col && row === weak.row) v = weak.rate;
      else if (row === band.row && col >= band.fromCol && col < band.fromCol + band.cells)
        v = band.rate;
      else if (col === speck.col && row === speck.row) v = speck.rate;
      values[row * width + col] = v;
    }
  }
  const buffer = writeArrayBuffer(values, {
    width,
    height,
    SamplesPerPixel: 1,
    BitsPerSample: [32],
    SampleFormat: [3],
    PhotometricInterpretation: 1,
    ModelPixelScale: [1000, 1000, 0],
    ModelTiepoint: [0, 0, 0, x0, y0, 0],
    // The key directory exactly as the real files carry it: projected model,
    // raster as area, geographic WGS 84 (EPSG 4326), Transverse Mercator (1)
    // in metres (9001), the natural origin's longitude and latitude in the
    // double parameters; no scale factor, no false origin.
    GeoKeyDirectory: [
      1, 1, 0, 7,
      1024, 0, 1, 1,
      1025, 0, 1, 1,
      2048, 0, 1, 4326,
      3075, 0, 1, 1,
      3076, 0, 1, 9001,
      3080, 34736, 1, 0,
      3081, 34736, 1, 1,
    ],
    GeoDoubleParams: [12.5, 42],
    // Named too, or the writer takes the image for a world map in degrees
    // and puts its own tie point in.
    ProjectedCSTypeGeoKey: 32767,
  });
  return new Uint8Array(buffer);
}
