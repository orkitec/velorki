// SPDX-License-Identifier: AGPL-3.0-only

/**
 * The per-device Plus records the apps write into the rider's own cloud
 * (`app/lib/features/sync/application/plus_id_sync.dart`): one record per
 * install, named `plus_<device id>`, of type `PlusDevice`, with the
 * install's RevenueCat app user id, its platform and when it last synced.
 * Only this relay reads them; the browser never sees an id.
 */

export const PLUS_RECORD_TYPE = 'PlusDevice';
export const PLUS_RECORD_PREFIX = 'plus_';

/** A record not seen for this long is ignored: the device stopped syncing there. */
export const FRESH_FOR_MS = 30 * 24 * 3_600_000;

/** At most this many ids are checked with RevenueCat per request. */
export const MAX_IDS = 10;

export interface PlusDevice {
  appUserId: string;
  platform: string;
  lastSeenMs: number;
}

/** A RevenueCat id as the app makes them: bounded, URL-safe, not a Plus token. */
function plausibleId(id: string): boolean {
  if (id.length === 0 || id.length > 256 || id.startsWith('vpt')) return false;
  return /^[\x21-\x7e]+$/.test(id);
}

/** A number of milliseconds out of whatever the cloud stored (a number or a digit string). */
export function millis(value: unknown): number | undefined {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && /^\d{1,16}$/.test(value)) return Number(value);
  return undefined;
}

/** A device out of loose fields, or undefined when one is missing or malformed. */
export function deviceOf(fields: {
  appUserId: unknown;
  platform: unknown;
  lastSeen: unknown;
}): PlusDevice | undefined {
  const { appUserId, platform } = fields;
  const lastSeenMs = millis(fields.lastSeen);
  if (typeof appUserId !== 'string' || !plausibleId(appUserId) || lastSeenMs === undefined) {
    return undefined;
  }
  return {
    appUserId,
    platform: typeof platform === 'string' ? platform.slice(0, 16) : 'unknown',
    lastSeenMs,
  };
}

/** The ids of the devices seen in the last 30 days, newest first, each once, at most `MAX_IDS`. */
export function freshIds(devices: readonly PlusDevice[], now: number): string[] {
  const fresh = devices
    .filter((d) => now - d.lastSeenMs <= FRESH_FOR_MS)
    .sort((a, b) => b.lastSeenMs - a.lastSeenMs);
  const ids: string[] = [];
  for (const d of fresh) {
    if (!ids.includes(d.appUserId)) ids.push(d.appUserId);
    if (ids.length >= MAX_IDS) break;
  }
  return ids;
}
