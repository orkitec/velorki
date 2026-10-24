// SPDX-License-Identifier: AGPL-3.0-only
import type { MetadataRoute } from 'next';
import { contentFile, docSlugs, listDocs, publishedLegalDocs, translatedLocales } from '@/site/content';
import { lastModified } from '@/site/lastmod';
import { LOCALES, languageAlternates, localeUrl } from '@/site/paths';

/** How prominent each legal document is; they are listed only when published. */
const LEGAL_PRIORITY: Record<string, number> = { privacy: 0.4, terms: 0.4, imprint: 0.3 };

interface SitemapPage {
  path: string;
  priority: number;
  changeFrequency: 'weekly' | 'monthly' | 'yearly';
  /** The locales the page is written in. */
  locales: readonly string[];
  /** The files (relative to web/) a locale's text comes from; its lastmod is the latest of their changes. */
  files: (locale: string) => string[];
}

const messages = (locale: string) => [`messages/${locale}.json`];

/**
 * Every published page, in every locale it is written in, each with its
 * hreflang alternates and the date its text last changed.
 *
 * A `draft: true` text is not offered to a crawler: it renders with `noindex`,
 * so listing it here would be the sitemap contradicting the page. Neither is
 * a locale that serves the English text with a notice (the imprint outside
 * English and German): that page is `noindex` too, and its hreflang set leaves
 * it out. The web planner is on its own host and is not listed here.
 */
export default function sitemap(): MetadataRoute.Sitemap {
  const docs = listDocs('en').filter((doc) => !doc.draft);
  const pages: SitemapPage[] = [
    { path: '/', priority: 1, changeFrequency: 'weekly', locales: LOCALES, files: messages },
    { path: '/download', priority: 0.9, changeFrequency: 'weekly', locales: LOCALES, files: messages },
    { path: '/plus', priority: 0.8, changeFrequency: 'monthly', locales: LOCALES, files: messages },
    {
      path: '/docs',
      priority: 0.8,
      changeFrequency: 'weekly',
      locales: LOCALES,
      // The index lists every page's title and description.
      files: (locale) => [
        ...messages(locale),
        ...docSlugs().flatMap((slug) => contentFile(locale, 'docs', slug) ?? []),
      ],
    },
    { path: '/credits', priority: 0.4, changeFrequency: 'yearly', locales: LOCALES, files: messages },
    ...docs.map((doc) => ({
      path: `/docs/${doc.slug}`,
      priority: 0.7,
      changeFrequency: 'monthly' as const,
      locales: translatedLocales('docs', doc.slug),
      files: (locale: string) => [contentFile(locale, 'docs', doc.slug) ?? []].flat(),
    })),
    ...publishedLegalDocs().map((doc) => ({
      path: `/${doc}`,
      priority: LEGAL_PRIORITY[doc] ?? 0.3,
      changeFrequency: 'yearly' as const,
      locales: translatedLocales('legal', doc),
      files: (locale: string) => [contentFile(locale, 'legal', doc) ?? []].flat(),
    })),
  ];

  return pages.flatMap((page) =>
    page.locales.map((locale) => {
      const modified = lastModified(page.files(locale));
      return {
        url: localeUrl(locale, page.path),
        ...(modified ? { lastModified: modified } : {}),
        changeFrequency: page.changeFrequency,
        priority: page.priority,
        alternates: { languages: languageAlternates(page.path, page.locales) },
      };
    }),
  );
}
