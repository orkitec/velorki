// SPDX-License-Identifier: AGPL-3.0-only
import { defineRouting } from 'next-intl/routing';
import { LOCALES, DEFAULT_LOCALE } from './locales.generated';

export const routing = defineRouting({
  locales: LOCALES,
  defaultLocale: DEFAULT_LOCALE,
  // English lives at the root; every other locale is prefixed (/de/...).
  localePrefix: 'as-needed',
  // A chosen language survives closing the browser; without maxAge next-intl
  // sets a session cookie and the system language wins again next time.
  localeCookie: { maxAge: 60 * 60 * 24 * 365 },
});

export type Locale = (typeof routing.locales)[number];
