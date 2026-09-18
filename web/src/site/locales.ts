// SPDX-License-Identifier: AGPL-3.0-only
import { LOCALES } from './paths';

/**
 * What each language calls itself. A locale switcher that translated its own
 * entries would be useless to the reader it exists for: someone who landed on
 * the German page by accident has to recognise "English", not "Englisch".
 * That is why these live here and not in messages/ - they are the same string
 * in every catalogue, and a new locale would otherwise need a name added to
 * every other language's file before it could be listed.
 *
 * A locale with no entry falls back to its code, so merging a translation
 * (messages/fr.json) lists it as "FR" rather than dropping it.
 */
const NATIVE_NAMES: Record<string, string> = {
  en: 'English',
  de: 'Deutsch',
};

/** The name of `locale` in `locale`, or its upper-cased code. */
export function localeName(locale: string): string {
  return NATIVE_NAMES[locale] ?? locale.toUpperCase();
}

/** Every locale the site is built in, with the name each one calls itself. */
export function localeNames(): ReadonlyArray<{ locale: string; name: string }> {
  return LOCALES.map((locale) => ({ locale, name: localeName(locale) }));
}
