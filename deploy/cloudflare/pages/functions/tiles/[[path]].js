// SPDX-License-Identifier: AGPL-3.0-only
//
// Pages Function for /tiles/*: the tile mirror under the app's origin.
// The logic lives in ../../tiles_proxy.mjs.

import { handleTiles } from '../../tiles_proxy.mjs';

export async function onRequest(context) {
  return handleTiles(context.request, {
    fetch: globalThis.fetch.bind(globalThis),
    cache: caches.default,
    waitUntil: context.waitUntil.bind(context),
  });
}
