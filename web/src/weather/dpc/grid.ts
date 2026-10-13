// SPDX-License-Identifier: AGPL-3.0-only
import { fromArrayBuffer } from 'geotiff';
import { CLASS_NO_DATA, classOfRate } from '../radar/classes';
import { geoKeyNumber, type ClassGrid } from '../radar/grid';
import type { TmercParams } from './tmerc';

/** One DPC frame's class grid, in the product's Transverse Mercator. */
export type DpcGrid = ClassGrid<TmercParams>;

/** GeoTIFF's code for a projected model (`GTModelTypeGeoKey`). */
const MODEL_PROJECTED = 1;
/** GeoTIFF's code for Transverse Mercator (`ProjCoordTransGeoKey`). */
const CT_TRANSVERSE_MERCATOR = 1;
/** GeoTIFF's code for metres (`ProjLinearUnitsGeoKey`). */
const LINEAR_METRE = 9001;
/** EPSG's WGS 84, as a geographic system and as an ellipsoid. */
const GCS_WGS84 = 4326;
const ELLIPSOID_WGS84 = 7030;

/**
 * The projection the file's GeoKeys name: Transverse Mercator in metres on
 * WGS 84, its natural origin, and the scale factor and false origin where
 * named (1 and 0 where not, as GeoTIFF has it; the DPC's files name
 * neither). Anything else is refused, since the drawing assumes it.
 */
export function tmercFromGeoKeys(keys: Record<string, unknown>): TmercParams {
  if (keys.GTModelTypeGeoKey !== undefined && keys.GTModelTypeGeoKey !== MODEL_PROJECTED) {
    throw new Error('DPC GeoTIFF: not projected');
  }
  if (keys.ProjCoordTransGeoKey !== CT_TRANSVERSE_MERCATOR) {
    throw new Error('DPC GeoTIFF: not Transverse Mercator');
  }
  if (keys.ProjLinearUnitsGeoKey !== undefined && keys.ProjLinearUnitsGeoKey !== LINEAR_METRE) {
    throw new Error('DPC GeoTIFF: not in metres');
  }
  if (
    keys.GeographicTypeGeoKey !== GCS_WGS84 &&
    keys.GeogEllipsoidGeoKey !== ELLIPSOID_WGS84
  ) {
    throw new Error('DPC GeoTIFF: not on WGS 84');
  }
  const optional = (name: string, fallback: number): number =>
    keys[name] === undefined ? fallback : geoKeyNumber(keys, name, 'DPC');
  return {
    lat0: geoKeyNumber(keys, 'ProjNatOriginLatGeoKey', 'DPC'),
    lon0: geoKeyNumber(keys, 'ProjNatOriginLongGeoKey', 'DPC'),
    k0: optional('ProjScaleAtNatOriginGeoKey', 1),
    falseEasting: optional('ProjFalseEastingGeoKey', 0),
    falseNorthing: optional('ProjFalseNorthingGeoKey', 0),
    a: 6378137,
    invFlattening: 298.257223563,
  };
}

/**
 * The class grid of one SRI GeoTIFF (`SRI/DD-MM-YYYY-HH-MM.tif`): surface
 * rainfall intensity in mm an hour, one float a cell, 0 dry, -9999 beyond
 * the radars' reach (any negative value and NaN are taken as no data too).
 * The rates are classed as they are: no reflectivity to convert.
 *
 * No clutter is dropped (OPERA's `dropClutter`): the SRI comes cleaned, and
 * the filter only hurts it. In nine frames of 2026-10-08 to 10-13 the
 * patches under four cells were 4 to 22 a frame, some 20 cells; the rule
 * against uniformly heavy patches dropped one patch of note, a
 * thunderstorm of 310 cells over the sea north of Sicily (38.0° N 14.1° E,
 * 01:40 UTC on the 13th) that the frames before and after show growing and
 * drifting east, its light rim around it.
 */
export async function decodeDpcTiff(bytes: Uint8Array): Promise<DpcGrid> {
  const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  const tiff = await fromArrayBuffer(buffer as ArrayBuffer);
  const image = await tiff.getImage(0);
  const keys = image.getGeoKeys();
  if (keys === null) throw new Error('DPC GeoTIFF: no GeoKeys');
  const proj = tmercFromGeoKeys(keys as Record<string, unknown>);
  const width = image.getWidth();
  const height = image.getHeight();
  const [x0, y0] = image.getOrigin();
  const [rx, ry] = image.getResolution();
  if (x0 === undefined || y0 === undefined || rx === undefined || ry === undefined) {
    throw new Error('DPC GeoTIFF: no georeference');
  }
  const noData = image.getGDALNoData();
  const rasters = await image.readRasters({ samples: [0], interleave: false });
  const values = rasters[0];
  if (values === undefined || values.length !== width * height) {
    throw new Error('DPC GeoTIFF: unexpected raster');
  }
  const cells = new Uint8Array(width * height);
  for (let i = 0; i < cells.length; i += 1) {
    const v = values[i] as number;
    if (Number.isNaN(v) || v < 0 || v === noData) cells[i] = CLASS_NO_DATA;
    else cells[i] = classOfRate(v);
  }
  return { width, height, x0, y0, dx: Math.abs(rx), dy: Math.abs(ry), proj, cells };
}

/**
 * The version of the shared grids: bumped whenever what a grid holds
 * changes, so those of an older one are fetched and decoded anew (their
 * cache keys name it) and expire unread.
 */
export const DPC_GRID_VERSION = 1;

/** The name and version a shared DPC grid's bytes start with. */
export const DPC_GRID_FORMAT = `velorki-dpc-grid-${String(DPC_GRID_VERSION)}`;
