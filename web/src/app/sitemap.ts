// SPDX-License-Identifier: AGPL-3.0-only
import type { MetadataRoute } from 'next';
import { docSlugs } from '@/site/content';
import { LOCALES, languageAlternates, localeUrl } from '@/site/paths';

/** Every page, in every locale, each with its hreflang alternates. */
export default function sitemap(): MetadataRoute.Sitemap {
  const pages: Array<{ path: string; priority: number; changeFrequency: 'weekly' | 'monthly' | 'yearly' }> = [
    { path: '/', priority: 1, changeFrequency: 'weekly' },
    { path: '/download', priority: 0.9, changeFrequency: 'weekly' },
    { path: '/plus', priority: 0.8, changeFrequency: 'monthly' },
    { path: '/docs', priority: 0.8, changeFrequency: 'weekly' },
    ...docSlugs().map((slug) => ({ path: `/docs/${slug}`, priority: 0.7, changeFrequency: 'monthly' as const })),
    { path: '/privacy', priority: 0.4, changeFrequency: 'yearly' },
    { path: '/terms', priority: 0.4, changeFrequency: 'yearly' },
    { path: '/imprint', priority: 0.3, changeFrequency: 'yearly' },
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
