// SPDX-License-Identifier: AGPL-3.0-only
// The structured data the site emits. Every builder returns a plain object; the
// <JsonLd> component serialises it into a single <script type="application/ld+json">.
import { GITHUB_URL, LICENSE_APP_URL, MIN_ANDROID, MIN_IOS, ORG_NAME, ORG_URL, SITE_URL } from './config';
import { localeUrl } from './paths';

export type JsonLdObject = Record<string, unknown>;

const ORGANIZATION_ID = `${SITE_URL}/#organization`;
const APPLICATION_ID = `${SITE_URL}/#app`;
const WEBSITE_ID = `${SITE_URL}/#website`;

/** Orkitec, the publisher. */
export function organizationJsonLd(): JsonLdObject {
  return {
    '@context': 'https://schema.org',
    '@type': 'Organization',
    '@id': ORGANIZATION_ID,
    name: ORG_NAME,
    url: ORG_URL,
    logo: `${SITE_URL}/icon.svg`,
    sameAs: [GITHUB_URL, ORG_URL],
  };
}

export function webSiteJsonLd(locale: string): JsonLdObject {
  return {
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    '@id': WEBSITE_ID,
    name: 'Velorki',
    url: localeUrl(locale, '/'),
    inLanguage: locale,
    publisher: { '@id': ORGANIZATION_ID },
  };
}

/**
 * The app itself. `MobileApplication` is the narrowest schema.org type that
 * fits (a subtype of SoftwareApplication), and `HealthAndFitnessApplication` is
 * the closest `applicationCategory` in schema.org's own enumeration for a
 * cycling route planner and ride recorder; `TravelApplication` is given as the
 * secondary category because the planner and the offline maps are as much of
 * the product as the recording is. The app is free: the offer is 0 EUR, and
 * Velorki Plus is a separate in-app subscription, not the price of the app.
 */
export function mobileApplicationJsonLd(description: string): JsonLdObject {
  return {
    '@context': 'https://schema.org',
    '@type': 'MobileApplication',
    '@id': APPLICATION_ID,
    name: 'Velorki',
    alternateName: 'Velorki: Bike Route Planner',
    url: SITE_URL,
    description,
    operatingSystem: [`Android ${MIN_ANDROID}+`, `iOS ${MIN_IOS}+`],
    applicationCategory: 'HealthAndFitnessApplication',
    applicationSubCategory: 'TravelApplication',
    isAccessibleForFree: true,
    offers: {
      '@type': 'Offer',
      price: '0',
      priceCurrency: 'EUR',
      availability: 'https://schema.org/InStock',
    },
    author: { '@id': ORGANIZATION_ID },
    publisher: { '@id': ORGANIZATION_ID },
    license: LICENSE_APP_URL,
    codeRepository: GITHUB_URL,
    isBasedOn: 'https://www.openstreetmap.org/',
    softwareHelp: `${SITE_URL}/docs`,
    privacyPolicy: `${SITE_URL}/privacy`,
    termsOfService: `${SITE_URL}/terms`,
  };
}

export interface FaqEntry {
  question: string;
  answer: string;
}

export function faqJsonLd(entries: FaqEntry[]): JsonLdObject {
  return {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: entries.map((entry) => ({
      '@type': 'Question',
      name: entry.question,
      acceptedAnswer: { '@type': 'Answer', text: entry.answer },
    })),
  };
}

export interface Crumb {
  name: string;
  path: string;
}

export function breadcrumbJsonLd(locale: string, crumbs: Crumb[]): JsonLdObject {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: crumbs.map((crumb, index) => ({
      '@type': 'ListItem',
      position: index + 1,
      name: crumb.name,
      item: localeUrl(locale, crumb.path),
    })),
  };
}

export interface ArticleSeed {
  locale: string;
  path: string;
  title: string;
  description: string;
}

/** One docs page as a TechArticle. */
export function techArticleJsonLd({ locale, path, title, description }: ArticleSeed): JsonLdObject {
  const url = localeUrl(locale, path);
  return {
    '@context': 'https://schema.org',
    '@type': 'TechArticle',
    headline: title,
    description,
    url,
    mainEntityOfPage: { '@type': 'WebPage', '@id': url },
    inLanguage: locale,
    author: { '@id': ORGANIZATION_ID },
    publisher: { '@id': ORGANIZATION_ID },
    about: { '@id': APPLICATION_ID },
    isPartOf: { '@id': WEBSITE_ID },
  };
}
