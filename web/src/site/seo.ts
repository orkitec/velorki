// SPDX-License-Identifier: AGPL-3.0-only
import type { Metadata } from 'next';
import { SITE_URL } from './config';
import { languageAlternates, localeUrl, pathAlternates } from './paths';

/**
 * The share card: `src/app/(site)/[locale]/og-card/route.tsx`, one per locale.
 * The route handler draws it at `OG_IMAGE_SIZE`, imported from here, so the
 * dimensions in the tag and the dimensions of the picture cannot drift apart.
 */
const OG_IMAGE_PATH = '/og-card';
export const OG_IMAGE_ALT = 'Velorki — plan the ride, follow the turns, offline';
export const OG_IMAGE_SIZE = { width: 1200, height: 630 };

/**
 * `og:image` for a locale, as an absolute URL.
 *
 * `localeUrl` applies the same `localePrefix: 'as-needed'` rule as every other
 * link on the site: no prefix for the default locale, `/de/...` for the rest.
 * That matters here - Next's own `opengraph-image.tsx` convention always
 * writes the prefixed path, next-intl strips `/en` again with a 307, and a
 * crawler that does not follow redirects ends up with no card at all.
 */
function ogImage(locale: string, image?: ShareImage): NonNullable<NonNullable<Metadata['openGraph']>['images']> {
  if (image) return [image];
  return [
    {
      url: localeUrl(locale, OG_IMAGE_PATH),
      alt: OG_IMAGE_ALT,
      type: 'image/png',
      ...OG_IMAGE_SIZE,
    },
  ];
}

/** A page's own share picture, as an absolute URL with its real size. */
export interface ShareImage {
  url: string;
  width: number;
  height: number;
  alt: string;
  type?: string;
}

/** Open Graph's article facts, for a blog post. */
export interface ArticleSeo {
  /** ISO dates, `YYYY-MM-DD`. */
  publishedTime: string;
  modifiedTime?: string;
  /** Absolute URLs of the author pages. */
  authors: string[];
  section?: string;
}

/** A feed the page announces with `<link rel="alternate">`. */
export interface FeedLink {
  /** Absolute URL. */
  url: string;
  title: string;
}

export interface PageSeo {
  locale: string;
  /** Path without the locale prefix, e.g. `/docs/getting-started`. */
  path: string;
  title: string;
  description: string;
  /** True for the landing page, whose title is the whole brand line. */
  absoluteTitle?: boolean;
  /** Share pages and the like; the site itself is fully indexable. */
  noIndex?: boolean;
  /**
   * With `noIndex`: still let a crawler follow the links. A blog index in a
   * language with no posts of its own is thin, but the posts it lists are not.
   */
  follow?: boolean;
  /** The locales the page is written in, for hreflang; every locale when omitted. */
  locales?: readonly string[];
  /**
   * Locale to path of each language version, for a page whose versions do not
   * share one path (a blog post and its translation). Wins over `locales`.
   */
  alternatePaths?: Readonly<Record<string, string>>;
  /** Makes the page an Open Graph `article`; a `website` without it. */
  article?: ArticleSeo;
  /** The page's own share picture; the locale's card when omitted. */
  image?: ShareImage;
  /** RSS feeds to announce. */
  feeds?: readonly FeedLink[];
}

/**
 * The metadata every page shares: canonical, hreflang for every locale plus
 * x-default, Open Graph and Twitter. The image is named explicitly rather than
 * left to Next's file-convention merge; see `ogImage` for why.
 */
export function pageMetadata({
  locale,
  path,
  title,
  description,
  absoluteTitle,
  noIndex,
  follow,
  locales,
  alternatePaths,
  article,
  image,
  feeds,
}: PageSeo): Metadata {
  const url = localeUrl(locale, path);
  const shareTitle = absoluteTitle ? title : `${title} · Velorki`;
  const base = {
    url,
    siteName: 'Velorki',
    title: shareTitle,
    description,
    locale,
    images: ogImage(locale, image),
  };
  return {
    title: absoluteTitle ? { absolute: title } : title,
    description,
    alternates: {
      canonical: url,
      languages: alternatePaths ? pathAlternates(alternatePaths, locale) : languageAlternates(path, locales),
      ...(feeds && feeds.length > 0
        ? { types: { 'application/rss+xml': feeds.map((feed) => ({ url: feed.url, title: feed.title })) } }
        : {}),
    },
    openGraph: article
      ? {
          ...base,
          type: 'article',
          publishedTime: article.publishedTime,
          ...(article.modifiedTime ? { modifiedTime: article.modifiedTime } : {}),
          authors: article.authors,
          ...(article.section ? { section: article.section } : {}),
        }
      : { ...base, type: 'website' },
    twitter: {
      card: 'summary_large_image',
      title: shareTitle,
      description,
      images: ogImage(locale, image),
    },
    robots: noIndex
      ? { index: false, follow: follow === true }
      : { index: true, follow: true, googleBot: { index: true, follow: true, 'max-image-preview': 'large', 'max-snippet': -1, 'max-video-preview': -1 } },
  };
}

/** `metadataBase`, so every relative URL in metadata resolves. */
export const METADATA_BASE = new URL(SITE_URL);
