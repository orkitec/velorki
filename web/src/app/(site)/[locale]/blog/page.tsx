// SPDX-License-Identifier: AGPL-3.0-only
import type { Metadata } from 'next';
import { getTranslations, setRequestLocale } from 'next-intl/server';
import { CategoryFilter, FeedLink, PostList } from '@/components/BlogList';
import { Breadcrumbs } from '@/components/DocsNav';
import { JsonLd } from '@/components/JsonLd';
import { blogIndexed, blogListing, FEED_PATH, indexedBlogLocales } from '@/site/blog';
import { breadcrumbJsonLd } from '@/site/jsonld';
import { localePath, localeUrl } from '@/site/paths';
import { pageMetadata } from '@/site/seo';

export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: 'blog' });
  return pageMetadata({
    locale,
    path: '/blog',
    title: t('meta.title'),
    description: t('meta.description'),
    // A language with no posts of its own lists only English ones: not a page
    // for a search engine, but the posts it links to are.
    noIndex: !blogIndexed(locale),
    follow: true,
    alternatePaths: Object.fromEntries(indexedBlogLocales().map((l) => [l, '/blog'])),
    feeds: [{ url: localeUrl(locale, FEED_PATH), title: t('feedTitle') }],
  });
}

export default async function BlogIndexPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({ locale, namespace: 'blog' });
  const docs = await getTranslations({ locale, namespace: 'docs' });
  const { own, english } = blogListing(locale);
  return (
    <div className="shell py-8 lg:py-12">
      <Breadcrumbs items={[{ name: docs('home'), href: localePath(locale, '/') }, { name: t('breadcrumb') }]} />
      <h1 className="text-4xl sm:text-5xl">{t('title')}</h1>
      <p className="mt-4 max-w-2xl text-lg text-muted">{t('lead')}</p>
      <FeedLink locale={locale} />
      <CategoryFilter locale={locale} />
      {own.length > 0 ? (
        <div className="mt-10">
          <PostList locale={locale} posts={own} />
        </div>
      ) : (
        english.length === 0 && <p className="mt-10 max-w-2xl text-muted">{t('empty')}</p>
      )}
      {english.length > 0 && (
        <section aria-labelledby="blog-in-english" className="mt-12">
          <h2 id="blog-in-english" className="overline mb-4">
            {t('inEnglish')}
          </h2>
          <PostList locale={locale} posts={english} heading="h3" />
        </section>
      )}
      <JsonLd
        data={breadcrumbJsonLd(locale, [
          { name: 'Velorki', path: '/' },
          { name: t('breadcrumb'), path: '/blog' },
        ])}
      />
    </div>
  );
}
