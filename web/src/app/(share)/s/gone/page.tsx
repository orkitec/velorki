// SPDX-License-Identifier: AGPL-3.0-only
import { notFound } from 'next/navigation';

/**
 * The 404 for a share link that does not exist any more.
 *
 * Under `cacheComponents` every dynamic route streams a static shell first, so
 * a `notFound()` inside `/s/[id]` arrives after the 200 has been committed and
 * only ever produces a soft 404. Next's own answer is to settle the question in
 * the proxy and rewrite to a not-found route: this page. It reads nothing, so
 * it is not streamed, and a `notFound()` in a non-streamed response is a real
 * 404 with the `(share)` group's `not-found.tsx` as its body.
 *
 * `/s/gone` is unreachable from outside - `gone` is not a well-formed share id,
 * so the proxy answers its JSON 404 before the router ever sees it.
 */
export default function ShareGone(): never {
  notFound();
}
