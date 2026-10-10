// SPDX-License-Identifier: AGPL-3.0-only

export const HOUR_MS = 3_600_000;

export function floorHour(ms: number): number {
  return Math.floor(ms / HOUR_MS) * HOUR_MS;
}

/** `2026-10-11T06:00:00Z`: the contract's form, without milliseconds. */
export function isoHour(ms: number): string {
  return new Date(ms).toISOString().replace('.000Z', 'Z');
}

/**
 * An ISO-8601 duration in whole hours (`PT1H`, `PT2H`, `P1D`, `P1DT6H`,
 * `PT90M`), or undefined when it is not one. Years and months never occur in
 * a forecast interval and are refused rather than guessed.
 */
export function durationHours(value: string): number | undefined {
  const m = /^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/.exec(value);
  if (m === null || value === 'P' || value.endsWith('T')) return undefined;
  const [, w, d, h, min, s] = m.map((g) => (g === undefined ? 0 : Number(g)));
  const hours =
    (w ?? 0) * 168 + (d ?? 0) * 24 + (h ?? 0) + (min ?? 0) / 60 + (s ?? 0) / 3600;
  const whole = Math.round(hours);
  return whole >= 1 ? whole : undefined;
}

/**
 * The full hours an ISO-8601 interval (`2026-10-10T13:00:00+00:00/PT2H`)
 * spans, as epoch ms of each hour's start.
 */
export function intervalHours(validTime: string): number[] {
  const [startText, durationText] = validTime.split('/');
  if (startText === undefined || durationText === undefined) return [];
  const start = Date.parse(startText);
  const hours = durationHours(durationText);
  if (Number.isNaN(start) || hours === undefined) return [];
  const first = floorHour(start);
  return Array.from({ length: hours }, (_, i) => first + i * HOUR_MS);
}

export function lerp(a: number, b: number, f: number): number {
  return a + (b - a) * f;
}

/** Interpolate a direction the short way round, so 350° to 10° passes 0°. */
export function lerpAngle(a: number, b: number, f: number): number {
  const delta = ((((b - a) % 360) + 540) % 360) - 180;
  return (((a + delta * f) % 360) + 360) % 360;
}

export function round(value: number, decimals: number): number {
  const p = 10 ** decimals;
  return Math.round(value * p) / p;
}
