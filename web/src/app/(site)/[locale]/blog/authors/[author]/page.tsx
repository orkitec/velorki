// SPDX-License-Identifier: AGPL-3.0-only
import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { getTranslations, setRequestLocale } from 'next-intl/server';
import { FeedLink, PostList } from '@/components/BlogList';
import { Breadcrumbs } from '@/components/DocsNav';
import { JsonLd } from '@/components/JsonLd';
import { routing } from '@/i18n/routing';
import { AUTHOR_IDS, findAuthor } from '@/site/authors';
import { authorIndexed, authorPath, blogListing, FEED_PATH, indexedAuthorLocales, postsIn } from '@/site/blog';
import { breadcrumbJsonLd } from '@/site/jsonld';
import { localePath, localeUrl } from '@/site/paths';
import { pageMetadata } from '@/site/seo';

interface AuthorParams {
  locale: string;
  author: string;
}

export function generateStaticParams(): AuthorParams[] {
  return routing.locales.flatMap((locale) => AUTHOR_IDS.map((author) => ({ locale, author })));
}

export async function generateMetadata({ params }: { params: Promise<AuthorParams> }): Promise<Metadata> {
  const { locale, author: id } = await params;
  const author = findAuthor(id);
  if (author === null) return {};
  const t = await getTranslations({ locale, namespace: 'blog' });
  return pageMetadata({
    locale,
    path: authorPath(author.id),
    title: author.name,
    description: t('authorDescription', { name: author.name }),
    // The index's rule: indexed in a language once they have published a
    // post of their own in it.
    noIndex: !authorIndexed(locale, author.id),
    follow: true,
    alternatePaths: Object.fromEntries(indexedAuthorLocales(author.id).map((l) => [l, authorPath(author.id)])),
    feeds: [{ url: localeUrl(locale, FEED_PATH), title: t('feedTitle') }],
  });
}

export default async function BlogAuthorPage({ params }: { params: Promise<AuthorParams> }) {
  const { locale, author: id } = await params;
  setRequestLocale(locale);
  const author = findAuthor(id);
  if (author === null) notFound();
  const t = await getTranslations({ locale, namespace: 'blog' });
  const docs = await getTranslations({ locale, namespace: 'docs' });
  const { own, english } = blogListing(
    locale,
    postsIn(locale).filter((post) => post.author === author.id),
  );
  const englishHere = english.filter((post) => post.author === author.id);
  return (
    <div className="shell py-8 lg:py-12">
      <Breadcrumbs
        items={[
          { name: docs('home'), href: localePath(locale, '/') },
          { name: t('breadcrumb'), href: localePath(locale, '/blog') },
          { name: author.name },
        ]}
      />
      <h1 className="text-4xl sm:text-5xl">{author.name}</h1>
      <p className="mt-4 max-w-2xl text-lg text-muted" lang="en">
        {author.role}
      </p>
      <p className="mt-4 text-sm">
        <a href={author.url} rel="me noreferrer" className="link-accent">
          {author.url.replace(/^https?:\/\//, '')}
        </a>
      </p>
      <FeedLink locale={locale} />
      <h2 className="overline mt-10 mb-4">{t('postsBy', { name: author.name })}</h2>
      {own.length > 0 && <PostList locale={locale} posts={own} heading="h3" />}
      {own.length === 0 && englishHere.length === 0 && <p className="max-w-2xl text-muted">{t('empty')}</p>}
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
          { name: author.name, path: authorPath(author.id) },
        ])}
      />
    </div>
  );
}
