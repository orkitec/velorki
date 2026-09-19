// SPDX-License-Identifier: AGPL-3.0-only
// The build-time half of the screenshot manifest: which files the pipeline has
// actually produced, and in which language. Server components only — it
// touches the filesystem.
import { existsSync } from 'node:fs';
import path from 'node:path';
import {
  ACCENTS,
  DEFAULT_SHOT_LOCALE,
  MODES,
  SCREENS,
  type Screen,
  type ScreenshotLocales,
  type VariantKey,
  variantKey,
} from './screenshots';
import type { LookAvailability } from './appearance';

/**
 * Which variants of `screen` are on disk for a page in `locale`, and which
 * language's file each of them is. The pipeline takes one language at a time
 * (`app/tool/screenshots.sh --lang de`), so a set can be complete in English
 * and pending in German: the fallback to `en` is per file, not per language.
 *
 * The result is a plain object of strings so it can cross to the client
 * component that swaps the image when the appearance switcher changes; a
 * variant with no file in either language is left out, and the frame shows a
 * placeholder naming the file it wanted.
 */
export function availableVariants(screen: Screen, locale: string): ScreenshotLocales {
  const available: ScreenshotLocales = {};
  const languages = locale === DEFAULT_SHOT_LOCALE ? [DEFAULT_SHOT_LOCALE] : [locale, DEFAULT_SHOT_LOCALE];
  for (const mode of MODES) {
    for (const accent of ACCENTS) {
      const key: VariantKey = variantKey(mode, accent);
      for (const language of languages) {
        const file = path.join(process.cwd(), 'public', 'screenshots', language, key, `${screen}.png`);
        if (existsSync(file)) {
          available[key] = language;
          break;
        }
      }
    }
  }
  return available;
}

/**
 * Every look a page in `locale` can show: the key of each variant that has at
 * least one screen on disk, in that language or in English. The appearance
 * switcher needs it before anything is clicked — a chip is off only where the
 * pipeline has taken nothing — so the landing page reads it here, on the
 * server, and hands it to `AppearanceProvider`. Capture a look with
 * `app/tool/screenshots.sh` and its chip lights up at the next build; no list
 * of "light is Volt only" is kept anywhere.
 */
export function availableLooks(locale: string): LookAvailability {
  const looks = new Set<string>();
  for (const screen of SCREENS) {
    for (const key of Object.keys(availableVariants(screen, locale))) looks.add(key);
  }
  return looks;
}
