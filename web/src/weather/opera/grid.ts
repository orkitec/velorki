// SPDX-License-Identifier: AGPL-3.0-only
import { fromArrayBuffer } from 'geotiff';
import { CLASS_DRY, CLASS_NO_DATA, classOfDbz } from '../radar/classes';
import { dropClutter, geoKeyNumber, type ClassGrid } from '../radar/grid';
import type { LaeaParams } from './laea';

/** One OPERA frame's class grid, in the composite's Lambert azimuthal equal-area. */
export type OperaGrid = ClassGrid<LaeaParams>;

/** GeoTIFF's code for Lambert Azimuthal Equal Area (`ProjCoordTransGeoKey`). */
const CT_LAMBERT_AZIM_EQUAL_AREA = 10;
/** GeoTIFF's code for metres (`ProjLinearUnitsGeoKey`). */
const LINEAR_METRE = 9001;
/** EPSG's WGS 84 ellipsoid, which the composite names by code. */
const ELLIPSOID_WGS84 = 7030;

/** Anything at or below this is the composite's fill value (-9 999 000). */
const FILL_BELOW = -9e6;

function num(keys: Record<string, unknown>, name: string): number {
  return geoKeyNumber(keys, name, 'OPERA');
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
): Promise<OperaGrid> {
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
 * The version of the shared grids: bumped whenever what a grid holds
 * changes (2: [dropClutter]), so those of an older one are fetched and
 * decoded anew (their cache keys name it) and expire unread.
 */
export const GRID_VERSION = 2;

/** The name and version a shared OPERA grid's bytes start with. */
export const OPERA_GRID_FORMAT = `velorki-opera-grid-${String(GRID_VERSION)}`;
