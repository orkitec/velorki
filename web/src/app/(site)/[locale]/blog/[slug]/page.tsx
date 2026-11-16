// SPDX-License-Identifier: AGPL-3.0-only
import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getTranslations, setRequestLocale } from 'next-intl/server';
import { Breadcrumbs, DraftNotice } from '@/components/DocsNav';
import { JsonLd } from '@/components/JsonLd';
import { PostRouteMap } from '@/components/PostRouteMap';
import { PostToc } from '@/components/PostToc';
import { Prose } from '@/components/Prose';
import { TocSpy } from '@/components/TocSpy';
import { findAuthor } from '@/site/authors';
import { SITE_URL } from '@/site/config';
import {
  authorPath,
  categoryPath,
  coverImage,
  findPost,
  formatPostDate,
  mediaPath,
  postPath,
  renderPost,
} from '@/site/blog';
import { postMetadata, postStaticParams } from '@/site/blog-pages';
import { blogPostingJsonLd, breadcrumbJsonLd } from '@/site/jsonld';
import { localePath, localeUrl } from '@/site/paths';
import { docToc } from '@/site/toc';

interface PostParams {
  locale: string;
  slug: string;
}

/**
 * Each post in its own locale only: `/de/blog/<english-slug>` is not
 * generated, and the proxy answers it with a real 404 before it gets here.
 */
export function generateStaticParams(): PostParams[] {
  return postStaticParams();
}

export async function generateMetadata({ params }: { params: Promise<PostParams> }): Promise<Metadata> {
  const { locale, slug } = await params;
  const post = findPost(locale, slug);
  if (post === null) return {};
  const t = await getTranslations({ locale, namespace: 'blog' });
  return postMetadata(post, { feedTitle: t('feedTitle'), section: t(`categories.${post.category}`) });
}

export default async function BlogPostPage({ params }: { params: Promise<PostParams> }) {
  const { locale, slug } = await params;
  setRequestLocale(locale);
  // The second line of defence; see generateStaticParams.
  const post = findPost(locale, slug);
  if (post === null) notFound();
  const author = findAuthor(post.author)!;
  const t = await getTranslations({ locale, namespace: 'blog' });
  const docs = await getTranslations({ locale, namespace: 'docs' });
  const { html, headings, readingMinutes } = renderPost(post);
  const sections = docToc(headings);
  const cover = coverImage(post);
  const category = t(`categories.${post.category}`);
  return (
    // The docs' columns: the post's sections on the left from `lg`, so a long
    // read has its outline beside it and the text column is not the only
    // thing on a wide screen.
    // The article is as wide as `.prose` (44rem in globals.css), so the cover
    // ends where the text and its pictures do.
    <div className="shell grid gap-8 py-8 lg:grid-cols-[15rem_minmax(0,1fr)] lg:gap-16 lg:py-12">
      <PostToc label={t('onThisPage')} sections={sections} />
      <article className={`min-w-0 max-w-[44rem] ${sections.length === 0 ? 'lg:col-span-2' : ''}`}>
        <Breadcrumbs
          items={[
            { name: docs('home'), href: localePath(locale, '/') },
            { name: t('breadcrumb'), href: localePath(locale, '/blog') },
            { name: post.title },
          ]}
        />
        {post.draft && <DraftNotice />}
        <h1 className="text-4xl sm:text-5xl">{post.title}</h1>
        <p className="mt-4 text-lg text-muted">{post.description}</p>
        <p className="mt-6 flex flex-wrap items-center gap-x-1.5 gap-y-1 text-sm text-muted">
          <time dateTime={post.date}>{formatPostDate(post.date, locale)}</time>
          {post.updated && (
            <>
              <span aria-hidden="true">·</span>
              <time dateTime={post.updated}>{t('updated', { date: formatPostDate(post.updated, locale) })}</time>
            </>
          )}
          <span aria-hidden="true">·</span>
          <span>
            {t.rich('byline', {
              name: author.name,
              author: (chunks) => (
                <Link href={localePath(locale, authorPath(author.id))} rel="author" className="text-fg hover:text-accent">
                  {chunks}
                </Link>
              ),
            })}
          </span>
          <span aria-hidden="true">·</span>
          <span>{t('readingTime', { minutes: readingMinutes })}</span>
          <span aria-hidden="true">·</span>
          <Link href={localePath(locale, categoryPath(post.category))} className="hover:text-fg">
            {category}
          </Link>
        </p>
        {cover && (
          // The cover is the first thing on screen, so it is not lazy. Plain
          // `<img>`: the file is already the size the author chose, and the
          // image optimiser would need a native dependency this app does not
          // take (web/README.md).
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={cover.src}
            width={cover.width}
            height={cover.height}
            alt={cover.alt}
            fetchPriority="high"
            className="mt-8 h-auto w-full rounded-[var(--radius-panel)]"
          />
        )}
        {post.gpx && (
          <section className="mt-8">
            <PostRouteMap gpxUrl={mediaPath(post, post.gpx)} label={t('mapLabel')} errorMessage={t('mapError')} />
            <p className="mt-4">
              <a href={mediaPath(post, post.gpx)} download={post.gpx} className="btn btn-secondary">
                {t('downloadGpx')}
              </a>
            </p>
          </section>
        )}
        <Prose html={html} className="mt-10" />
      </article>
      {sections.length > 0 && <TocSpy ids={headings.map((heading) => heading.id)} />}
      <JsonLd
        data={[
          blogPostingJsonLd({
            locale,
            path: postPath(post),
            title: post.title,
            description: post.description,
            datePublished: post.date,
            ...(post.updated ? { dateModified: post.updated } : {}),
            ...(cover ? { image: `${SITE_URL}${cover.src}` } : {}),
            author: {
              name: author.name,
              url: localeUrl(locale, authorPath(author.id)),
              sameAs: author.sameAs,
            },
            section: category,
          }),
          // The names are the visible ones, so the German page does not claim
          // an English trail.
          breadcrumbJsonLd(locale, [
            { name: 'Velorki', path: '/' },
            { name: t('breadcrumb'), path: '/blog' },
            { name: post.title, path: postPath(post) },
          ]),
        ]}
      />
    </div>
  );
}
