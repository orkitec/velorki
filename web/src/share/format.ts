// SPDX-License-Identifier: AGPL-3.0-only
import type { ShareRecord } from './store';

/** Presentation helpers for the public share page and the GPX download. */

export function formatDistance(km: number): string {
  return `${km.toFixed(1)} km`;
}

export function formatAscent(m: number): string {
  return `${String(Math.round(m))} m`;
}

export function formatDuration(seconds: number): string {
  const total = Math.round(seconds);
  const h = Math.floor(total / 3600);
  const min = Math.floor((total % 3600) / 60);
  return h > 0 ? `${String(h)} h ${String(min).padStart(2, '0')} min` : `${String(min)} min`;
}

export interface Stat {
  label: string;
  value: string;
}

export function shareStats(record: ShareRecord): Stat[] {
  const stats: Stat[] = [
    { label: 'Distance', value: formatDistance(record.summary.distance_km) },
  ];
  if (record.summary.ascent_m !== undefined) {
    stats.push({ label: 'Ascent', value: formatAscent(record.summary.ascent_m) });
  }
  if (record.summary.duration_s !== undefined) {
    stats.push({ label: 'Duration', value: formatDuration(record.summary.duration_s) });
  }
  return stats;
}

export function shareKindLabel(record: ShareRecord): string {
  return record.kind === 'ride' ? 'Ride' : 'Route';
}

export function shareTitle(record: ShareRecord): string {
  return record.name || 'Velorki route';
}

/** ASCII-safe filename derived from the share name, with the id as a fallback. */
export function gpxFilename(name: string, id: string): string {
  const slug = name
    .normalize('NFKD')
    .replace(/[^\w -]/g, '')
    .trim()
    .replace(/\s+/g, '-')
    .slice(0, 60);
  return `${slug === '' ? `velorki-${id}` : slug}.gpx`;
}
