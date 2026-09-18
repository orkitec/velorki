// SPDX-License-Identifier: AGPL-3.0-only
import type { MetadataRoute } from 'next';
import { listDocs, publishedLegalDocs } from '@/site/content';
import { LOCALES, languageAlternates, localeUrl } from '@/site/paths';

/** How prominent each legal document is; they are listed only when published. */
const LEGAL_PRIORITY: Record<string, number> = { privacy: 0.4, terms: 0.4, imprint: 0.3 };

/**
 * Every published page, in every locale, each with its hreflang alternates.
 * A `draft: true` text is not offered to a crawler: it renders with `noindex`,
 * so listing it here would be the sitemap contradicting the page.
 */
export default function sitemap(): MetadataRoute.Sitemap {
  const pages: Array<{ path: string; priority: number; changeFrequency: 'weekly' | 'monthly' | 'yearly' }> = [
    { path: '/', priority: 1, changeFrequency: 'weekly' },
    { path: '/download', priority: 0.9, changeFrequency: 'weekly' },
    { path: '/plus', priority: 0.8, changeFrequency: 'monthly' },
    { path: '/docs', priority: 0.8, changeFrequency: 'weekly' },
    { path: '/credits', priority: 0.4, changeFrequency: 'yearly' },
    ...listDocs('en')
      .filter((doc) => !doc.draft)
      .map((doc) => ({ path: `/docs/${doc.slug}`, priority: 0.7, changeFrequency: 'monthly' as const })),
    ...publishedLegalDocs().map((doc) => ({
      path: `/${doc}`,
      priority: LEGAL_PRIORITY[doc] ?? 0.3,
      changeFrequency: 'yearly' as const,
    })),
  ];

  return pages.flatMap((page) =>
    LOCALES.map((locale) => ({
      url: localeUrl(locale, page.path),
      changeFrequency: page.changeFrequency,
      priority: page.priority,
      alternates: { languages: languageAlternates(page.path) },
    })),
  );
}
