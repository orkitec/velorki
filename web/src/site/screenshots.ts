// SPDX-License-Identifier: AGPL-3.0-only
// The screenshot manifest: pure data, no filesystem, so client components can
// import it too. The build-time existence check lives in screenshot-files.ts.
// `app/tool/screenshots.sh` writes
// public/screenshots/<lang>/<mode>-<accent>/<screen>.png; the site knows the
// grid of files it may ask for, checks at build time which of them exist, and
// renders a labelled placeholder for the rest, so the pages are complete
// before the pipeline has run.
export const MODES = ['dark', 'light'] as const;
export const ACCENTS = ['volt', 'ember', 'glacier', 'berry', 'forest'] as const;
export const SCREENS = [
  'planner',
  'loop',
  'search',
  'navigation',
  'recording',
  'ride',
  'library',
  'offline',
  'settings',
] as const;

export type Mode = (typeof MODES)[number];
export type Accent = (typeof ACCENTS)[number];
export type Screen = (typeof SCREENS)[number];

/** The variant shown before anything is switched: the app's own default look. */
export const DEFAULT_MODE: Mode = 'dark';
export const DEFAULT_ACCENT: Accent = 'volt';

/**
 * The language every set is taken in first, and what a page falls back to for
 * a screen the pipeline has not captured in the page's own language yet. It is
 * `app/tool/screenshots.sh --lang`'s default, and the directory the English
 * shots live in.
 */
export const DEFAULT_SHOT_LOCALE = 'en';

/** Captured at the emulator's native resolution; see public/screenshots/README.md. */
export const SHOT_WIDTH = 1080;
export const SHOT_HEIGHT = 2400;

export type VariantKey = `${Mode}-${Accent}`;

export function variantKey(mode: Mode, accent: Accent): VariantKey {
  return `${mode}-${accent}`;
}

/**
 * Which language's file to use for each variant of one screen, by variant key.
 * `screenshot-files.ts` fills it in on the server at build time — the page's
 * own locale where that file exists, `en` where it does not — and a variant
 * with no file at all is simply absent, so the frame shows its placeholder.
 */
export type ScreenshotLocales = Record<string, string>;

/** The public path of one screenshot. */
export function screenshotSrc(locale: string, mode: Mode, accent: Accent, screen: Screen): string {
  return `/screenshots/${locale}/${variantKey(mode, accent)}/${screen}.png`;
}

/**
 * The variant to show for a wanted mode and accent: the exact one if it is
 * there, else the same mode in volt, else the default, else none at all. The
 * language comes with it, because the fallback to `en` is per file: a set may
 * be complete in one look and pending in another.
 */
export function resolveVariant(
  available: ScreenshotLocales,
  mode: Mode,
  accent: Accent,
): { mode: Mode; accent: Accent; locale: string } | null {
  const candidates: Array<{ mode: Mode; accent: Accent }> = [
    { mode, accent },
    { mode, accent: DEFAULT_ACCENT },
    { mode: DEFAULT_MODE, accent },
    { mode: DEFAULT_MODE, accent: DEFAULT_ACCENT },
  ];
  for (const candidate of candidates) {
    const locale = available[variantKey(candidate.mode, candidate.accent)];
    if (locale) return { ...candidate, locale };
  }
  return null;
}
