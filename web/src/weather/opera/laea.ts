// SPDX-License-Identifier: AGPL-3.0-only
import type { GridProjection } from '../radar/render';

/**
 * Lambert Azimuthal Equal Area on an ellipsoid (Snyder, "Map Projections - A
 * Working Manual", pp. 187-190; EPSG method 9820), forward only: the OPERA
 * composite is drawn by asking, for each pixel of a Web Mercator image, which
 * cell of the composite's grid lies under it.
 *
 * The OPERA CIRRUS composite's GeoTIFF keys name this projection
 * (`ProjCoordTransGeoKey` 10) centred on 55° N 10° E, false easting 1 950 000,
 * false northing -2 100 000, on the WGS 84 ellipsoid; `grid.ts` reads them
 * from each file rather than trusting these numbers.
 */
export interface LaeaParams {
  /** Latitude of the centre, degrees. */
  lat0: number;
  /** Longitude of the centre, degrees. */
  lon0: number;
  falseEasting: number;
  falseNorthing: number;
  /** Semi-major axis, metres. */
  a: number;
  /** Inverse flattening. */
  invFlattening: number;
}

const DEG = Math.PI / 180;

/** The constants of one projection, worked out once. */
export class Laea implements GridProjection {
  readonly params: LaeaParams;
  readonly #e: number;
  readonly #e2: number;
  readonly #qp: number;
  readonly #rq: number;
  readonly #d: number;
  readonly #sinB1: number;
  readonly #cosB1: number;
  readonly #lon0: number;

  constructor(params: LaeaParams) {
    this.params = params;
    const f = 1 / params.invFlattening;
    this.#e2 = f * (2 - f);
    this.#e = Math.sqrt(this.#e2);
    this.#qp = this.#q(1);
    this.#rq = params.a * Math.sqrt(this.#qp / 2);
    const phi1 = params.lat0 * DEG;
    const sin1 = Math.sin(phi1);
    const beta1 = Math.asin(this.#q(sin1) / this.#qp);
    this.#sinB1 = Math.sin(beta1);
    this.#cosB1 = Math.cos(beta1);
    const m1 = Math.cos(phi1) / Math.sqrt(1 - this.#e2 * sin1 * sin1);
    this.#d = (params.a * m1) / (this.#rq * this.#cosB1);
    this.#lon0 = params.lon0 * DEG;
  }

  /** Snyder's q of a latitude whose sine is `s`. */
  #q(s: number): number {
    const e = this.#e;
    const es = e * s;
    return (1 - this.#e2) * (s / (1 - es * es) - (1 / (2 * e)) * Math.log((1 - es) / (1 + es)));
  }

  /**
   * The authalic latitude's sine and cosine of `lat` (degrees): the part of
   * the forward projection that depends on the latitude alone, so a whole row
   * of an image shares it.
   */
  beta(lat: number): { sin: number; cos: number } {
    const sinB = this.#q(Math.sin(lat * DEG)) / this.#qp;
    const clamped = Math.max(-1, Math.min(1, sinB));
    return { sin: clamped, cos: Math.sqrt(1 - clamped * clamped) };
  }

  /** The angle from the centre's meridian of `lon` (degrees), radians. */
  dLon(lon: number): number {
    return lon * DEG - this.#lon0;
  }

  /**
   * Projected x and y, metres, false easting and northing included, from a
   * latitude's [beta] and a longitude's [dLon] (as sine and cosine). `null`
   * at the antipode, where the projection has no point.
   */
  forwardParts(
    sinB: number,
    cosB: number,
    sinL: number,
    cosL: number,
  ): { x: number; y: number } | null {
    const denom = 1 + this.#sinB1 * sinB + this.#cosB1 * cosB * cosL;
    if (denom <= 1e-12) return null;
    const b = this.#rq * Math.sqrt(2 / denom);
    return {
      x: this.params.falseEasting + b * this.#d * cosB * sinL,
      y:
        this.params.falseNorthing +
        (b / this.#d) * (this.#cosB1 * sinB - this.#sinB1 * cosB * cosL),
    };
  }

  /** Projected x and y, metres, of `lat`, `lon` in degrees. */
  forward(lat: number, lon: number): { x: number; y: number } | null {
    const { sin, cos } = this.beta(lat);
    const dl = this.dLon(lon);
    return this.forwardParts(sin, cos, Math.sin(dl), Math.cos(dl));
  }

  /** See [GridProjection.lattice]: the latitudes' [beta] and longitudes' [dLon] once each. */
  lattice(
    lats: Float64Array,
    lons: Float64Array,
  ): (row: number, col: number) => { x: number; y: number } | null {
    const sinL = new Float64Array(lons.length);
    const cosL = new Float64Array(lons.length);
    lons.forEach((lon, c) => {
      const dl = this.dLon(lon);
      sinL[c] = Math.sin(dl);
      cosL[c] = Math.cos(dl);
    });
    const sinB = new Float64Array(lats.length);
    const cosB = new Float64Array(lats.length);
    lats.forEach((lat, r) => {
      const beta = this.beta(lat);
      sinB[r] = beta.sin;
      cosB[r] = beta.cos;
    });
    return (r, c) => this.forwardParts(sinB[r] ?? 0, cosB[r] ?? 0, sinL[c] ?? 0, cosL[c] ?? 1);
  }
}
