// SPDX-License-Identifier: AGPL-3.0-only
// Which screenshot set a page shows, as rules rather than as state: the site's
// own palette, what the visitor picked in the appearance switcher, and which
// looks the pipeline has actually captured. Pure, so the switcher, the phone
// frames and the tests all agree — the DOM reading that feeds it lives in
// components/Appearance.tsx.
import { DEFAULT_ACCENT, type Accent, type Mode, type VariantKey, variantKey } from './screenshots';

/**
 * Whether the pipeline takes `accent` in `mode`. Light is captured in Volt
 * only, the app's default accent; the four other accents exist in dark.
 * `resolveVariant` would fall back on its own, but the switcher has to say so
 * on the chip, before anybody clicks it.
 */
export function accentExists(mode: Mode, accent: Accent): boolean {
  return mode === 'dark' || accent === DEFAULT_ACCENT;
}

/** The variant the frames render: a mode, an accent that exists in it, the key. */
export interface Look {
  mode: Mode;
  accent: Accent;
  key: VariantKey;
}

/**
 * The look for a page view.
 *
 * `site` is the palette the page itself is painted in, and is what the tour
 * shows until the visitor picks a side: a reader on a light site sees the app
 * in light. `picked` is that pick, and wins for the rest of the page view —
 * nothing about it is remembered across a reload.
 *
 * `accent` is kept as chosen even where no light shot exists for it: the look
 * falls back to Volt for as long as the mode is light, and the visitor's accent
 * comes back the moment it is dark again.
 */
export function resolveLook({
  site,
  picked = null,
  accent = DEFAULT_ACCENT,
}: {
  site: Mode;
  picked?: Mode | null;
  accent?: Accent;
}): Look {
  const mode = picked ?? site;
  const shown = accentExists(mode, accent) ? accent : DEFAULT_ACCENT;
  return { mode, accent: shown, key: variantKey(mode, shown) };
}
