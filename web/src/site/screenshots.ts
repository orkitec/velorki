// SPDX-License-Identifier: AGPL-3.0-only
// The screenshot manifest: pure data, no filesystem, so client components can
// import it too. The build-time existence check lives in screenshot-files.ts.
// `app/tool/screenshots.sh` writes
// public/screenshots/<mode>-<accent>/<screen>.png; the site knows the grid of
// files it may ask for, checks at build time which of them exist, and renders a
// labelled placeholder for the rest, so the pages are complete before the
// pipeline has run.
export const MODES = ['dark', 'light'] as const;
export const ACCENTS = ['volt', 'ember', 'glacier', 'berry'] as const;
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

/** Captured at the emulator's native resolution; see public/screenshots/README.md. */
export const SHOT_WIDTH = 1080;
export const SHOT_HEIGHT = 2400;

export type VariantKey = `${Mode}-${Accent}`;

export function variantKey(mode: Mode, accent: Accent): VariantKey {
  return `${mode}-${accent}`;
}

/** The public path of one screenshot. */
export function screenshotSrc(mode: Mode, accent: Accent, screen: Screen): string {
  return `/screenshots/${variantKey(mode, accent)}/${screen}.png`;
}

/**
 * The variant to show for a wanted mode and accent: the exact one if it is
 * there, else the same mode in volt, else the default, else none at all.
 */
export function resolveVariant(
  available: Record<string, boolean>,
  mode: Mode,
  accent: Accent,
): { mode: Mode; accent: Accent } | null {
  const candidates: Array<{ mode: Mode; accent: Accent }> = [
    { mode, accent },
    { mode, accent: DEFAULT_ACCENT },
    { mode: DEFAULT_MODE, accent },
    { mode: DEFAULT_MODE, accent: DEFAULT_ACCENT },
  ];
  for (const candidate of candidates) {
    if (available[variantKey(candidate.mode, candidate.accent)]) return candidate;
  }
  return null;
}
