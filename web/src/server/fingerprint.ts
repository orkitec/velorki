// SPDX-License-Identifier: AGPL-3.0-only
import { createHash } from 'node:crypto';

/**
 * A short, stable tag for a secret, so a log line can say *which* key is live
 * without saying what it is.
 *
 * Secrets set in the Orkify dashboard are write-only - nobody can read them
 * back - which is right, and makes "did the new key arrive?" unanswerable. The
 * boot log therefore prints `sha256:` plus the first 8 hex digits of each set
 * secret. Compute the same locally to compare:
 *
 *   printf %s "$KEY" | sha256sum | cut -c1-8
 *
 * Eight hex digits of a hash reveal nothing usable about a high-entropy API
 * key; they only let you tell two keys apart.
 */
export function fingerprint(value: string | undefined): string | null {
  if (value === undefined || value === '') return null;
  return `sha256:${createHash('sha256').update(value, 'utf8').digest('hex').slice(0, 8)}`;
}
