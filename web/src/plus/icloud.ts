// SPDX-License-Identifier: AGPL-3.0-only
import type { Config } from '@/config';
import { ApiError } from '@/server/errors';
import type { FetchLike } from '@/server/entitlement';
import { FRESH_FOR_MS, PLUS_RECORD_TYPE, deviceOf, type PlusDevice } from './devices';

/**
 * The Plus records in the rider's iCloud private database, zone `Library`,
 * read through CloudKit Web Services with the web API token
 * (`CLOUDKIT_API_TOKEN`) and the web auth token the browser got from
 * CloudKit JS's sign-in.
 *
 * Apple documents the web auth token as one round trip each: the answer
 * brings a new one and the one sent stops working. Whatever new token the
 * answer carries goes back to the browser, which must use it from then on.
 * The API token's allowed origins are matched against `Origin`, which is
 * sent as `CLOUDKIT_ORIGIN`. Both are Apple's to change: if CloudKit stops
 * taking the browser's token from a server, the browser would have to
 * query the records itself, which would mean trusting ids it sends.
 *
 * The query filters on `lastSeen`, so the `PlusDevice` type needs
 * `lastSeen` queryable in the deployed schema (docs/SYNC_SETUP.md).
 */

const BASE = 'https://api.apple-cloudkit.com/database/1';
const MAX_PAGES = 3;

interface CkField {
  value?: unknown;
}

interface CkRecord {
  recordName?: string;
  recordType?: string;
  fields?: Record<string, CkField | undefined>;
  serverErrorCode?: string;
}

interface CkAnswer {
  records?: CkRecord[];
  continuationMarker?: string;
  serverErrorCode?: string;
  reason?: string;
  ckWebAuthToken?: string;
}

export interface ICloudResult {
  devices: PlusDevice[];
  /** The web auth token to use from now on, when CloudKit handed out a new one. */
  webAuthToken?: string;
}

const AUTH_ERRORS = new Set(['AUTHENTICATION_REQUIRED', 'AUTHENTICATION_FAILED', 'ACCESS_DENIED']);

export async function icloudDevices(
  config: Config,
  webAuthToken: string,
  now: number,
  fetchImpl: FetchLike = (input, init) => globalThis.fetch(input, init),
  log?: { warn: (obj: object, msg: string) => void },
): Promise<ICloudResult> {
  const apiToken = config.CLOUDKIT_API_TOKEN;
  if (apiToken === undefined) {
    throw new ApiError('unavailable', 'iCloud is not configured on this server.');
  }
  const devices: PlusDevice[] = [];
  let token = webAuthToken;
  let rotated: string | undefined;
  let marker: string | undefined;
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const url = new URL(
      `${BASE}/${encodeURIComponent(config.CLOUDKIT_CONTAINER)}/${config.CLOUDKIT_ENVIRONMENT}/private/records/query`,
    );
    url.searchParams.set('ckAPIToken', apiToken);
    // URLSearchParams encodes '+', '/' and '=' as Apple asks.
    url.searchParams.set('ckWebAuthToken', token);
    const body = {
      zoneID: { zoneName: 'Library' },
      resultsLimit: 50,
      desiredKeys: ['appUserId', 'platform', 'lastSeen'],
      query: {
        recordType: PLUS_RECORD_TYPE,
        filterBy: [
          {
            fieldName: 'lastSeen',
            comparator: 'GREATER_THAN',
            fieldValue: { value: now - FRESH_FOR_MS, type: 'INT64' },
          },
        ],
      },
      ...(marker === undefined ? {} : { continuationMarker: marker }),
    };
    let res: Response;
    try {
      res = await fetchImpl(url, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          accept: 'application/json',
          origin: config.CLOUDKIT_ORIGIN,
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(8_000),
      });
    } catch (cause) {
      log?.warn({ err: String(cause) }, 'cloudkit request failed');
      throw new ApiError('upstream_error', 'Could not reach iCloud.');
    }
    let answer: CkAnswer = {};
    try {
      answer = (await res.json()) as CkAnswer;
    } catch {
      if (res.ok) throw new ApiError('upstream_error', 'iCloud returned an invalid response.');
    }
    const next =
      res.headers.get('x-apple-cloudkit-web-auth-token') ?? answer.ckWebAuthToken ?? undefined;
    if (next !== undefined && next !== '') {
      token = next;
      rotated = next;
    }
    const code = answer.serverErrorCode;
    if (code === 'ZONE_NOT_FOUND') {
      // Nothing ever synced into this account.
      return rotated === undefined ? { devices } : { devices, webAuthToken: rotated };
    }
    if (res.status === 401 || res.status === 421 || (code !== undefined && AUTH_ERRORS.has(code))) {
      throw new ApiError('not_entitled', 'iCloud did not accept the sign-in.', {
        reason: 'cloud_auth',
      });
    }
    if (!res.ok || code !== undefined) {
      // A schema without PlusDevice or its index answers BAD_REQUEST here.
      log?.warn({ status: res.status, code, reason: answer.reason }, 'cloudkit upstream error');
      throw new ApiError('upstream_error', 'iCloud is unavailable.');
    }
    for (const record of answer.records ?? []) {
      if (record.serverErrorCode !== undefined || record.recordType !== PLUS_RECORD_TYPE) continue;
      const f = record.fields ?? {};
      const device = deviceOf({
        appUserId: f.appUserId?.value,
        platform: f.platform?.value,
        lastSeen: f.lastSeen?.value,
      });
      if (device !== undefined) devices.push(device);
    }
    marker = answer.continuationMarker;
    if (marker === undefined || marker === '') break;
  }
  return rotated === undefined ? { devices } : { devices, webAuthToken: rotated };
}
