// SPDX-License-Identifier: AGPL-3.0-only
// Which screenshot set a page shows, as rules rather than as state: the site's
// own palette, what the visitor picked in the appearance switcher, and which
// looks the pipeline has actually captured. Pure, so the switcher, the phone
// frames and the tests all agree — the availability comes in as a value, read
// off the disk at build time by site/screenshot-files.ts, and the DOM reading
// that feeds the rest lives in components/Appearance.tsx.
import { DEFAULT_ACCENT, type Accent, type Mode, type VariantKey, variantKey } from './screenshots';

/**
 * The looks a page may show: the keys of the sets the pipeline has on disk for
 * that page's locale, English included, because the fallback to `en` is per
 * file. `screenshot-files.ts` builds it on the server; the provider hands it
 * down, so nothing here has to guess which accents were captured.
 */
export type LookAvailability = ReadonlySet<string>;

/** No set on disk at all: every chip is off and every frame falls back. */
export const NO_LOOKS: LookAvailability = new Set<string>();

/**
 * Whether the pipeline has taken `accent` in `mode` for this page. The
 * switcher asks before anybody clicks a chip, `resolveLook` asks again when it
 * picks the file, and both read the same set of captured looks — so adding a
 * language or a look to `app/tool/screenshots.sh` is all it takes to light a
 * chip up.
 */
export function accentExists(available: LookAvailability, mode: Mode, accent: Accent): boolean {
  return available.has(variantKey(mode, accent));
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
 * `accent` is kept as chosen even where no shot exists for it in this mode:
 * the look falls back to Volt for as long as that is so, and the visitor's
 * accent comes back the moment the other mode has it.
 */
export function resolveLook({
  site,
  picked = null,
  accent = DEFAULT_ACCENT,
  available = NO_LOOKS,
}: {
  site: Mode;
  picked?: Mode | null;
  accent?: Accent;
  available?: LookAvailability;
}): Look {
  const mode = picked ?? site;
  const shown = accentExists(available, mode, accent) ? accent : DEFAULT_ACCENT;
  return { mode, accent: shown, key: variantKey(mode, shown) };
}
