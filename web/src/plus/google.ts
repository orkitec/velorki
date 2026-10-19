// SPDX-License-Identifier: AGPL-3.0-only
import { ApiError } from '@/server/errors';
import type { FetchLike } from '@/server/entitlement';
import { PLUS_RECORD_PREFIX, PLUS_RECORD_TYPE, deviceOf, type PlusDevice } from './devices';

/**
 * The Plus records in the rider's Google Drive app data folder, read with
 * the browser's own access token (scope `drive.appdata`). The Drive store
 * keeps one file per record, its name the record name and its fields in
 * the file's `appProperties` (`kind`, `appUserId`, `platform`, `lastSeen`),
 * with no content.
 */

const FILES_URL = 'https://www.googleapis.com/drive/v3/files';
const MAX_PAGES = 5;

interface DriveFile {
  name?: string;
  appProperties?: Record<string, unknown>;
}

interface DriveList {
  files?: DriveFile[];
  nextPageToken?: string;
}

export async function googleDevices(
  accessToken: string,
  fetchImpl: FetchLike = (input, init) => globalThis.fetch(input, init),
  log?: { warn: (obj: object, msg: string) => void },
): Promise<PlusDevice[]> {
  const devices: PlusDevice[] = [];
  let pageToken: string | undefined;
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const url = new URL(FILES_URL);
    url.searchParams.set('spaces', 'appDataFolder');
    url.searchParams.set('q', `name contains '${PLUS_RECORD_PREFIX}' and trashed = false`);
    url.searchParams.set('fields', 'nextPageToken,files(name,appProperties)');
    url.searchParams.set('pageSize', '100');
    if (pageToken !== undefined) url.searchParams.set('pageToken', pageToken);
    let res: Response;
    try {
      res = await fetchImpl(url, {
        headers: { authorization: `Bearer ${accessToken}`, accept: 'application/json' },
        signal: AbortSignal.timeout(8_000),
      });
    } catch (cause) {
      log?.warn({ err: String(cause) }, 'drive request failed');
      throw new ApiError('upstream_error', 'Could not reach Google Drive.');
    }
    if (res.status === 401 || res.status === 403) {
      // Expired, revoked, or without the drive.appdata scope. (A 403 is also
      // Google's rate limit; the rider signing in again is right for both.)
      throw new ApiError('not_entitled', 'Google did not accept the sign-in.', {
        reason: 'cloud_auth',
      });
    }
    if (!res.ok) {
      log?.warn({ status: res.status }, 'drive upstream error');
      throw new ApiError('upstream_error', 'Google Drive is unavailable.');
    }
    let body: DriveList;
    try {
      body = (await res.json()) as DriveList;
    } catch {
      throw new ApiError('upstream_error', 'Google Drive returned an invalid response.');
    }
    for (const file of body.files ?? []) {
      const props = file.appProperties ?? {};
      if (!file.name?.startsWith(PLUS_RECORD_PREFIX)) continue;
      if (props.kind !== undefined && props.kind !== PLUS_RECORD_TYPE) continue;
      const device = deviceOf({
        appUserId: props.appUserId,
        platform: props.platform,
        lastSeen: props.lastSeen,
      });
      if (device !== undefined) devices.push(device);
    }
    pageToken = body.nextPageToken;
    if (pageToken === undefined || pageToken === '') break;
  }
  return devices;
}
