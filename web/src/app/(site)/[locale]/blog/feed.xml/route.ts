// SPDX-License-Identifier: AGPL-3.0-only
// The blog's RSS 2.0 feed per locale: `/blog/feed.xml`, `/de/blog/feed.xml`.
// A language's feed carries its own posts and the English ones, as its index
// does (src/site/blog.ts, feedPosts). The path carries an extension, so the
// proxy names it in its matcher and maps the English one onto this route
// itself rather than through locale negotiation: a feed reader asking for
// `/blog/feed.xml` must get the English feed, whatever its Accept-Language.
import { getTranslations } from 'next-intl/server';
import { routing } from '@/i18n/routing';
import { BLOG_CATEGORIES, feedXml } from '@/site/blog';

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function GET(_request: Request, ctx: { params: Promise<{ locale: string }> }): Promise<Response> {
  const { locale } = await ctx.params;
  const t = await getTranslations({ locale, namespace: 'blog' });
  const body = feedXml(locale, {
    title: t('feedTitle'),
    description: t('meta.description'),
    categories: Object.fromEntries(BLOG_CATEGORIES.map((category) => [category, t(`categories.${category}`)])) as Record<
      (typeof BLOG_CATEGORIES)[number],
      string
    >,
  });
  return new Response(body, {
    headers: {
      'content-type': 'application/rss+xml; charset=utf-8',
      'cache-control': 'public, max-age=3600',
    },
  });
}
