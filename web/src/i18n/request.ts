// SPDX-License-Identifier: AGPL-3.0-only
import { getRequestConfig } from 'next-intl/server';
import { hasLocale } from 'next-intl';
import { routing } from './routing';

export default getRequestConfig(async ({ requestLocale }) => {
  const requested = await requestLocale;
  const locale = hasLocale(routing.locales, requested) ? requested : routing.defaultLocale;
  // A locale whose catalogue is missing keys falls back to English per key.
  type Catalogue = { default: Record<string, unknown> };
  const base = (await import(`../../messages/en.json`)) as Catalogue;
  const own = (await import(`../../messages/${locale}.json`)) as Catalogue;
  const messages = { ...base.default, ...own.default };
  return { locale, messages };
});
