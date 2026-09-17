// SPDX-License-Identifier: AGPL-3.0-only
import type { JsonLdObject } from '@/site/jsonld';

/**
 * One `application/ld+json` block. `<` is escaped so a string from content can
 * never close the script element early.
 */
export function JsonLd({ data }: { data: JsonLdObject | JsonLdObject[] }) {
  const json = JSON.stringify(data).replace(/</g, '\\u003c');
  return <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: json }} />;
}
