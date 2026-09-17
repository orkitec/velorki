// SPDX-License-Identifier: AGPL-3.0-only
import { defineRouting } from 'next-intl/routing';
import { LOCALES, DEFAULT_LOCALE } from './locales.generated';

export const routing = defineRouting({
  locales: LOCALES,
  defaultLocale: DEFAULT_LOCALE,
  // English lives at the root; every other locale is prefixed (/de/...).
  localePrefix: 'as-needed',
});

export type Locale = (typeof routing.locales)[number];
