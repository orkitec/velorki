// SPDX-License-Identifier: AGPL-3.0-only
import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { connection } from 'next/server';
import { getStore } from '@/server/singletons';
import { isValidShareId, type ShareRecord } from '@/share/store';
import ShareDetails from './ShareDetails';
import ShareMap from './ShareMap';

/**
 * A share link is a capability, not a public document: it must never end up in
 * a search index.
 */
export const metadata: Metadata = {
  title: 'Shared route - Velorki',
  robots: { index: false, follow: false },
};

/**
 * The page reads the request outside a Suspense boundary, which under
 * `cacheComponents` is a build error unless the segment says it is allowed to
 * block. It is: there is nothing worth streaming a shell for, the body is one
 * indexed SELECT in the same process.
 */
export const instant = false;

/**
 * The lookup behind the page. Exported so a test can drive it directly: the
 * page body around it is a single `notFound()` branch.
 *
 * The proxy already rejects a malformed id, but the page must not depend on a
 * caller for that - an id that is not well-formed never reaches SQL. Unknown
 * and expired ids both come back as `null`.
 */
export function loadShare(id: string): ShareRecord | null {
  return isValidShareId(id) ? getStore().get(id) : null;
}

/**
 * One store read, before any markup. The store reads the clock to decide
 * whether a share has expired, so this is request-time by definition.
 *
 * `notFound()` here is the second line of defence, not the first: the proxy has
 * already asked the store whether the id exists and rewritten the misses to
 * `/s/gone`, because under `cacheComponents` a dynamic route streams a static
 * shell before this function runs and the 200 is committed by then. What is
 * left for this branch is the narrow race where a link expires between the two
 * reads - a soft 404 with the right body, which is the correct answer for a
 * link that was alive a millisecond ago.
 */
export default async function SharePage({ params }: { params: Promise<{ id: string }> }) {
  await connection();
  const { id } = await params;
  const record = loadShare(id);
  if (record === null) notFound();
  return <ShareDetails record={record} map={<ShareMap id={record.id} />} />;
}
