// SPDX-License-Identifier: AGPL-3.0-only
import type { GridProjection } from '../radar/render';

/**
 * Transverse Mercator on an ellipsoid (Snyder, "Map Projections - A Working
 * Manual", pp. 60-64, equations 8-9 to 8-15 and 3-21; EPSG method 9807),
 * forward only: the DPC's rainfall grid is drawn by asking, for each pixel
 * of a Web Mercator image, which cell lies under it.
 *
 * The DPC's SRI GeoTIFFs name this projection (`ProjCoordTransGeoKey` 1)
 * with its natural origin at 42° N 12.5° E on WGS 84 (`GeographicTypeGeoKey`
 * 4326) and no scale factor nor false origin (so 1 and 0, the GeoTIFF
 * defaults); `grid.ts` reads them from each file rather than trusting these
 * numbers. Snyder's series is good to well under a metre within the grid's
 * seven degrees of the central meridian, its cells are a kilometre.
 */
export interface TmercParams {
  /** Latitude of the natural origin, degrees. */
  lat0: number;
  /** Longitude of the natural origin (the central meridian), degrees. */
  lon0: number;
  /** Scale factor on the central meridian. */
  k0: number;
  falseEasting: number;
  falseNorthing: number;
  /** Semi-major axis, metres. */
  a: number;
  /** Inverse flattening. */
  invFlattening: number;
}

const DEG = Math.PI / 180;

/** The constants of one projection, worked out once. */
export class Tmerc implements GridProjection {
  readonly params: TmercParams;
  readonly #e2: number;
  readonly #ep2: number;
  readonly #m0: number;
  readonly #lon0: number;

  constructor(params: TmercParams) {
    this.params = params;
    const f = 1 / params.invFlattening;
    this.#e2 = f * (2 - f);
    this.#ep2 = this.#e2 / (1 - this.#e2);
    this.#m0 = this.#meridian(params.lat0 * DEG);
    this.#lon0 = params.lon0 * DEG;
  }

  /** The meridian's length from the equator to `phi` (radians), metres. */
  #meridian(phi: number): number {
    const e2 = this.#e2;
    const e4 = e2 * e2;
    const e6 = e4 * e2;
    return (
      this.params.a *
      ((1 - e2 / 4 - (3 * e4) / 64 - (5 * e6) / 256) * phi -
        ((3 * e2) / 8 + (3 * e4) / 32 + (45 * e6) / 1024) * Math.sin(2 * phi) +
        ((15 * e4) / 256 + (45 * e6) / 1024) * Math.sin(4 * phi) -
        ((35 * e6) / 3072) * Math.sin(6 * phi))
    );
  }

  /** What the forward projection needs of a latitude (degrees) alone. */
  #row(lat: number): { m: number; n: number; t: number; c: number; tan: number; cos: number } {
    const phi = lat * DEG;
    const sin = Math.sin(phi);
    const cos = Math.cos(phi);
    const tan = Math.tan(phi);
    return {
      m: this.#meridian(phi),
      n: this.params.a / Math.sqrt(1 - this.#e2 * sin * sin),
      t: tan * tan,
      c: this.#ep2 * cos * cos,
      tan,
      cos,
    };
  }

  /** Projected x and y from a latitude's [#row] and a longitude's angle from the central meridian. */
  #forward(
    row: { m: number; n: number; t: number; c: number; tan: number; cos: number },
    dLon: number,
  ): { x: number; y: number } {
    const { m, n, t, c, tan, cos } = row;
    const k0 = this.params.k0;
    const ep2 = this.#ep2;
    const a1 = dLon * cos;
    const a2 = a1 * a1;
    const a3 = a2 * a1;
    const a4 = a2 * a2;
    const a5 = a4 * a1;
    const a6 = a4 * a2;
    return {
      x:
        this.params.falseEasting +
        k0 * n * (a1 + ((1 - t + c) * a3) / 6 + ((5 - 18 * t + t * t + 72 * c - 58 * ep2) * a5) / 120),
      y:
        this.params.falseNorthing +
        k0 *
          (m -
            this.#m0 +
            n *
              tan *
              (a2 / 2 +
                ((5 - t + 9 * c + 4 * c * c) * a4) / 24 +
                ((61 - 58 * t + t * t + 600 * c - 330 * ep2) * a6) / 720)),
    };
  }

  /** Projected x and y, metres, of `lat`, `lon` in degrees. */
  forward(lat: number, lon: number): { x: number; y: number } {
    return this.#forward(this.#row(lat), lon * DEG - this.#lon0);
  }

  /** See [GridProjection.lattice]: each latitude's terms and longitude's angle once. */
  lattice(
    lats: Float64Array,
    lons: Float64Array,
  ): (row: number, col: number) => { x: number; y: number } | null {
    const rows = Array.from(lats, (lat) => this.#row(lat));
    const dLons = lons.map((lon) => lon * DEG - this.#lon0);
    return (r, c) => {
      const row = rows[r];
      return row === undefined ? null : this.#forward(row, dLons[c] ?? 0);
    };
  }
}
