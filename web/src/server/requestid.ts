// SPDX-License-Identifier: AGPL-3.0-only
import { randomUUID } from 'node:crypto';

export const REQUEST_ID_HEADER = 'x-request-id';

/**
 * Reuse a caller-supplied X-Request-Id when it looks sane, otherwise mint one.
 *
 * Bound the length and charset: the id goes straight back out in a header and
 * into the logs, so untrusted input must not be able to inject either.
 */
export function requestIdFrom(headers: Headers): string {
  const value = headers.get(REQUEST_ID_HEADER);
  if (value !== null) {
    const trimmed = value.trim();
    if (trimmed.length > 0 && trimmed.length <= 128 && /^[\w.:@/+-]+$/.test(trimmed)) {
      return trimmed;
    }
  }
  return randomUUID();
}
