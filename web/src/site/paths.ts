// SPDX-License-Identifier: AGPL-3.0-only
import { routing } from '@/i18n/routing';
import { SITE_URL } from './config';

/** Every locale the site is built in, English first. */
export const LOCALES = routing.locales;
export type SiteLocale = (typeof routing.locales)[number];

/**
 * The path a page has in `locale`. English is unprefixed (`localePrefix:
 * 'as-needed'`), so `/docs` is English and `/de/docs` is German.
 */
export function localePath(locale: string, path = '/'): string {
  const clean = path === '/' ? '' : `/${path.replace(/^\/+|\/+$/g, '')}`;
  if (locale === routing.defaultLocale) return clean === '' ? '/' : clean;
  return `/${locale}${clean}`;
}

/**
 * The path a locale switcher links to: always prefixed, `/en` included.
 * The unprefixed English path is the canonical one, but a rider who has
 * visited `/de` carries a NEXT_LOCALE=de cookie, and `/` would only send them
 * back there; `/en` resets the cookie and redirects to `/`.
 */
export function switchPath(locale: string, path = '/'): string {
  const clean = path === '/' ? '' : `/${path.replace(/^\/+|\/+$/g, '')}`;
  return `/${locale}${clean}`;
}

/** The absolute, canonical URL of `path` in `locale`. */
export function localeUrl(locale: string, path = '/'): string {
  const p = localePath(locale, path);
  return p === '/' ? `${SITE_URL}/` : `${SITE_URL}${p}`;
}

/**
 * `alternates.languages` for a page: one entry per locale plus `x-default`,
 * which points at the English version.
 */
export function languageAlternates(path = '/'): Record<string, string> {
  const languages: Record<string, string> = {};
  for (const locale of LOCALES) languages[locale] = localeUrl(locale, path);
  languages['x-default'] = localeUrl(routing.defaultLocale, path);
  return languages;
}
