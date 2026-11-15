// SPDX-License-Identifier: AGPL-3.0-only
import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { getTranslations, setRequestLocale } from 'next-intl/server';
import { CategoryFilter, FeedLink, PostList } from '@/components/BlogList';
import { Breadcrumbs } from '@/components/DocsNav';
import { JsonLd } from '@/components/JsonLd';
import { routing } from '@/i18n/routing';
import {
  BLOG_CATEGORIES,
  type BlogCategory,
  blogListing,
  categoryIndexed,
  categoryPath,
  FEED_PATH,
  indexedCategoryLocales,
  postsIn,
} from '@/site/blog';
import { breadcrumbJsonLd } from '@/site/jsonld';
import { localePath, localeUrl } from '@/site/paths';
import { pageMetadata } from '@/site/seo';

interface CategoryParams {
  locale: string;
  category: string;
}

export function generateStaticParams(): CategoryParams[] {
  return routing.locales.flatMap((locale) => BLOG_CATEGORIES.map((category) => ({ locale, category })));
}

function asCategory(value: string): BlogCategory | null {
  return (BLOG_CATEGORIES as readonly string[]).includes(value) ? (value as BlogCategory) : null;
}

export async function generateMetadata({ params }: { params: Promise<CategoryParams> }): Promise<Metadata> {
  const { locale, category: raw } = await params;
  const category = asCategory(raw);
  const t = await getTranslations({ locale, namespace: 'blog' });
  if (category === null) return {};
  return pageMetadata({
    locale,
    path: categoryPath(category),
    title: `${t(`categories.${category}`)} · ${t('title')}`,
    description: t(`categoryLead.${category}`),
    // Indexed in a language once it has a published post of its own in this
    // category; the same rule as the index (see blogIndexed).
    noIndex: !categoryIndexed(locale, category),
    follow: true,
    alternatePaths: Object.fromEntries(indexedCategoryLocales(category).map((l) => [l, categoryPath(category)])),
    feeds: [{ url: localeUrl(locale, FEED_PATH), title: t('feedTitle') }],
  });
}

export default async function BlogCategoryPage({ params }: { params: Promise<CategoryParams> }) {
  const { locale, category: raw } = await params;
  setRequestLocale(locale);
  const category = asCategory(raw);
  if (category === null) notFound();
  const t = await getTranslations({ locale, namespace: 'blog' });
  const docs = await getTranslations({ locale, namespace: 'docs' });
  const name = t(`categories.${category}`);
  const { own, english } = blogListing(
    locale,
    postsIn(locale).filter((post) => post.category === category),
  );
  const englishHere = english.filter((post) => post.category === category);
  return (
    <div className="shell py-8 lg:py-12">
      <Breadcrumbs
        items={[
          { name: docs('home'), href: localePath(locale, '/') },
          { name: t('breadcrumb'), href: localePath(locale, '/blog') },
          { name },
        ]}
      />
      <h1 className="text-4xl sm:text-5xl">{name}</h1>
      <p className="mt-4 max-w-2xl text-lg text-muted">{t(`categoryLead.${category}`)}</p>
      <FeedLink locale={locale} />
      <CategoryFilter locale={locale} current={category} />
      {own.length > 0 && (
        <div className="mt-10">
          <PostList locale={locale} posts={own} />
        </div>
      )}
      {own.length === 0 && englishHere.length === 0 && (
        <p className="mt-10 max-w-2xl text-muted">{t('emptyCategory')}</p>
      )}
      {englishHere.length > 0 && (
        <section aria-labelledby="blog-in-english" className="mt-12">
          <h2 id="blog-in-english" className="overline mb-4">
            {t('inEnglish')}
          </h2>
          <PostList locale={locale} posts={englishHere} heading="h3" />
        </section>
      )}
      <JsonLd
        data={breadcrumbJsonLd(locale, [
          { name: 'Velorki', path: '/' },
          { name: t('breadcrumb'), path: '/blog' },
          { name, path: categoryPath(category) },
        ])}
      />
    </div>
  );
}
