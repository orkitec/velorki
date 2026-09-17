// SPDX-License-Identifier: AGPL-3.0-only
import { notFoundResponse } from '@/server/errors';
import { REQUEST_ID_HEADER, requestIdFrom } from '@/server/requestid';
import { getConfig } from '@/server/singletons';

/**
 * Universal Links and App Links association files, reached through
 * next.config's rewrite of `/.well-known/:file`.
 *
 * Both are built from configuration. When the key for one of them is unset the
 * file 404s rather than being served empty: an unconfigured deployment (a fork,
 * a staging host) must not advertise an association it cannot honour, or the
 * platforms cache a broken one.
 */

const ANDROID_PACKAGE = 'com.orkitec.velorki';
const IOS_BUNDLE_ID = 'com.orkitec.velorki';
/** Only share links open the app; the rest of the site stays in the browser. */
const LINK_PATHS = ['/s/*'];

function jsonFile(body: unknown, requestId: string): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: {
      'content-type': 'application/json',
      'cache-control': 'public, max-age=3600',
      [REQUEST_ID_HEADER]: requestId,
    },
  });
}

export async function GET(
  request: Request,
  ctx: { params: Promise<{ file: string }> },
): Promise<Response> {
  const requestId = requestIdFrom(request.headers);
  const config = getConfig();
  const { file } = await ctx.params;

  if (file === 'apple-app-site-association') {
    if (config.APPLE_TEAM_ID === undefined) {
      return notFoundResponse('Not found.', { [REQUEST_ID_HEADER]: requestId });
    }
    return jsonFile(
      {
        applinks: {
          details: [
            {
              appIDs: [`${config.APPLE_TEAM_ID}.${IOS_BUNDLE_ID}`],
              paths: LINK_PATHS,
            },
          ],
        },
      },
      requestId,
    );
  }

  if (file === 'assetlinks.json') {
    if (config.ANDROID_CERT_SHA256.length === 0) {
      return notFoundResponse('Not found.', { [REQUEST_ID_HEADER]: requestId });
    }
    return jsonFile(
      [
        {
          relation: ['delegate_permission/common.handle_all_urls'],
          target: {
            namespace: 'android_app',
            package_name: ANDROID_PACKAGE,
            sha256_cert_fingerprints: config.ANDROID_CERT_SHA256,
          },
        },
      ],
      requestId,
    );
  }

  return notFoundResponse('Not found.', { [REQUEST_ID_HEADER]: requestId });
}
