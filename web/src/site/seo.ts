// SPDX-License-Identifier: AGPL-3.0-only
import type { Metadata } from 'next';
import { SITE_URL } from './config';
import { languageAlternates, localeUrl } from './paths';

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
function ogImage(locale: string): NonNullable<NonNullable<Metadata['openGraph']>['images']> {
  return [
    {
      url: localeUrl(locale, OG_IMAGE_PATH),
      alt: OG_IMAGE_ALT,
      type: 'image/png',
      ...OG_IMAGE_SIZE,
    },
  ];
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
}

/**
 * The metadata every page shares: canonical, hreflang for every locale plus
 * x-default, Open Graph and Twitter. The image is named explicitly rather than
 * left to Next's file-convention merge; see `ogImage` for why.
 */
export function pageMetadata({ locale, path, title, description, absoluteTitle, noIndex }: PageSeo): Metadata {
  const url = localeUrl(locale, path);
  return {
    title: absoluteTitle ? { absolute: title } : title,
    description,
    alternates: { canonical: url, languages: languageAlternates(path) },
    openGraph: {
      type: 'website',
      url,
      siteName: 'Velorki',
      title: absoluteTitle ? title : `${title} · Velorki`,
      description,
      locale,
      images: ogImage(locale),
    },
    twitter: {
      card: 'summary_large_image',
      title: absoluteTitle ? title : `${title} · Velorki`,
      description,
      images: ogImage(locale),
    },
    robots: noIndex
      ? { index: false, follow: false }
      : { index: true, follow: true, googleBot: { index: true, follow: true, 'max-image-preview': 'large', 'max-snippet': -1, 'max-video-preview': -1 } },
  };
}

/** `metadataBase`, so every relative URL in metadata resolves. */
export const METADATA_BASE = new URL(SITE_URL);
