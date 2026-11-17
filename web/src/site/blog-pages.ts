// SPDX-License-Identifier: AGPL-3.0-only
// What the blog's pages and files say about a post to the outside: static
// params, metadata, sitemap entries. Apart from the pages so a test can call
// it without next-intl's server runtime.
import type { MetadataRoute, Metadata } from 'next';
import { findAuthor } from './authors';
import {
  authorPath,
  type BlogPost,
  BLOG_CATEGORIES,
  categoryPath,
  coverImage,
  FEED_PATH,
  allMedia,
  allPosts,
  indexedAuthorLocales,
  indexedBlogLocales,
  indexedCategoryLocales,
  postFiles,
  postPath,
  postVersions,
  publishedPosts,
} from './blog';
import { AUTHOR_IDS } from './authors';
import { SITE_URL } from './config';
import { lastModified } from './lastmod';
import { routing } from '@/i18n/routing';
import { localeUrl, pathAlternates } from './paths';
import { OG_IMAGE_SIZE, pageMetadata } from './seo';

/**
 * hreflang for a listing that lives at the same path in each of `locales`
 * (the languages where it is indexed), with `x-default` on English only when
 * English is among them: a category with no English post is `noindex` in
 * English, and a default pointing there would point at nothing.
 */
export function listingAlternates(path: string, locales: readonly string[]): Record<string, string> {
  const paths = Object.fromEntries(locales.map((locale) => [locale, path]));
  return locales.length > 0 ? pathAlternates(paths, locales[0]!) : {};
}

/**
 * A slug no post can have (`_` is not allowed in one), for a build with no
 * posts: under `cacheComponents` every `generateStaticParams` must return at
 * least one entry, or the build fails. Its page is a 404, and the proxy never
 * lets a request reach it.
 */
export const NO_POST = '_none';

/** Every post at its own locale's address, and nowhere else. */
export function postStaticParams(): Array<{ locale: string; slug: string }> {
  const params = allPosts().map((post) => ({ locale: post.locale, slug: post.slug }));
  return params.length > 0 ? params : [{ locale: routing.defaultLocale, slug: NO_POST }];
}

/** Every file beside a post, for the media route; a placeholder when there is none (see NO_POST). */
export function mediaStaticParams(): Array<{ locale: string; slug: string; hash: string; file: string }> {
  const params = allMedia();
  return params.length > 0 ? params : [{ locale: routing.defaultLocale, slug: NO_POST, hash: NO_POST, file: NO_POST }];
}

/**
 * A post's metadata: an Open Graph article, hreflang only between the
 * versions that share its key (each at its own slug), and its cover as the
 * share picture, or the site's card drawn with its title.
 */
export function postMetadata(post: BlogPost, strings: { feedTitle: string; section: string }): Metadata {
  const author = findAuthor(post.author);
  const cover = coverImage(post);
  const image =
    cover?.width !== undefined && cover.height !== undefined
      ? { url: `${SITE_URL}${cover.src}`, width: cover.width, height: cover.height, alt: post.title }
      : {
          url: localeUrl(post.locale, `${postPath(post)}/og-card`),
          ...OG_IMAGE_SIZE,
          alt: post.title,
          type: 'image/png',
        };
  return pageMetadata({
    locale: post.locale,
    path: postPath(post),
    title: post.title,
    description: post.description,
    // Drafts only exist under `next dev`; still, never offer one.
    noIndex: post.draft,
    alternatePaths: postVersions(post),
    article: {
      publishedTime: post.date,
      ...(post.updated ? { modifiedTime: post.updated } : {}),
      authors: author ? [localeUrl(post.locale, authorPath(author.id))] : [],
      section: strings.section,
    },
    image,
    feeds: [{ url: localeUrl(post.locale, FEED_PATH), title: strings.feedTitle }],
  });
}

/** The day a post last changed: its files' last commit, else its front matter. */
function postModified(post: BlogPost): Date {
  return lastModified(postFiles(post)) ?? new Date(`${post.updated ?? post.date}T00:00:00Z`);
}

function latest(dates: readonly (Date | undefined)[]): Date | undefined {
  let newest: Date | undefined;
  for (const date of dates) if (date && (!newest || date > newest)) newest = date;
  return newest;
}

/**
 * The blog's sitemap entries: every published post in its own language only,
 * with the versions sharing its key as alternates; and each index, category
 * and author page in the languages where it is indexed (see blogIndexed).
 */
export function blogSitemap(): MetadataRoute.Sitemap {
  const published = publishedPosts();
  const posts = published.map((post) => {
    const modified = postModified(post);
    return {
      url: localeUrl(post.locale, postPath(post)),
      lastModified: modified,
      changeFrequency: 'monthly' as const,
      priority: 0.6,
      alternates: { languages: pathAlternates(postVersions(post, published), post.locale) },
    };
  });

  // A listing changes when one of the posts it shows does.
  const listing = (path: string, locales: readonly string[], shown: (locale: string) => BlogPost[]) =>
    locales.map((locale) => {
      const modified = latest(shown(locale).map(postModified));
      return {
        url: localeUrl(locale, path),
        ...(modified ? { lastModified: modified } : {}),
        changeFrequency: 'weekly' as const,
        priority: path === '/blog' ? 0.7 : 0.4,
        alternates: { languages: listingAlternates(path, locales) },
      };
    });
  const own = (locale: string) => published.filter((post) => post.locale === locale || post.locale === routing.defaultLocale);

  return [
    ...listing('/blog', indexedBlogLocales(), own),
    ...BLOG_CATEGORIES.flatMap((category) =>
      listing(categoryPath(category), indexedCategoryLocales(category), (locale) =>
        own(locale).filter((post) => post.category === category),
      ),
    ),
    ...AUTHOR_IDS.flatMap((author) =>
      listing(authorPath(author), indexedAuthorLocales(author), (locale) =>
        own(locale).filter((post) => post.author === author),
      ),
    ),
    ...posts,
  ];
}
