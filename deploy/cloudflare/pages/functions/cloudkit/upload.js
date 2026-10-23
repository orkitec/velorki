// SPDX-License-Identifier: AGPL-3.0-only
//
// Pages Function for /cloudkit/upload: CloudKit JS's asset upload under the
// app's origin. The logic lives in ../../cloudkit_upload.mjs.

import { handleUpload } from '../../cloudkit_upload.mjs';

export async function onRequest(context) {
  return handleUpload(context.request, {
    fetch: globalThis.fetch.bind(globalThis),
  });
}
