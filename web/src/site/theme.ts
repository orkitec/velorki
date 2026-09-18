// SPDX-License-Identifier: AGPL-3.0-only
// Which palette the site paints in. Pure, so the switcher, the no-flash script
// in the document head and the tests all agree on one set of rules.

/** The three states of the header's theme switch. */
export const THEMES = ['system', 'light', 'dark'] as const;

export type Theme = (typeof THEMES)[number];

/** What the choice is remembered under, in the reader's own browser. */
export const THEME_STORAGE_KEY = 'velorki.theme';

/** The state a reader who has never touched the switch is in. */
export const DEFAULT_THEME: Theme = 'system';

/**
 * The theme a stored value stands for: anything the site did not write — a
 * missing key, a stale value, a hand-edited one — is System.
 */
export function resolveTheme(stored: string | null | undefined): Theme {
  return THEMES.includes(stored as Theme) ? (stored as Theme) : DEFAULT_THEME;
}

/**
 * The value of `data-theme` on `<html>` for a choice, or `null` for System,
 * where the attribute is absent and `prefers-color-scheme` decides.
 */
export function themeAttribute(theme: Theme): 'light' | 'dark' | null {
  return theme === 'system' ? null : theme;
}

/**
 * The palette a page is actually painted in, from what a browser can see: the
 * attribute the switch (or `ThemeScript`) left on `<html>` when a reader forced
 * one, and `prefers-color-scheme` for everyone still on System. The counterpart
 * of `themeAttribute`, for the parts of the page that have to follow the site's
 * look rather than set it.
 */
export function paintedTheme(attribute: string | null | undefined, prefersDark: boolean): 'light' | 'dark' {
  if (attribute === 'light' || attribute === 'dark') return attribute;
  return prefersDark ? 'dark' : 'light';
}
