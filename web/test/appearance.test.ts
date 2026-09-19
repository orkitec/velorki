// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import { NO_LOOKS, accentExists, resolveLook } from '@/site/appearance';
import { ACCENTS, DEFAULT_ACCENT, DEFAULT_MODE, MODES, variantKey } from '@/site/screenshots';
import { paintedTheme } from '@/site/theme';

describe('the palette a page is painted in', () => {
  it('takes the forced attribute over the system preference', () => {
    expect(paintedTheme('light', true)).toBe('light');
    expect(paintedTheme('dark', false)).toBe('dark');
  });

  it('falls back to the system preference with no attribute, or a stray one', () => {
    for (const attribute of [null, undefined, '', 'system', 'Dark']) {
      expect(paintedTheme(attribute, true)).toBe('dark');
      expect(paintedTheme(attribute, false)).toBe('light');
    }
  });
});

// What `site/screenshot-files.ts` reads off disk at build time and the page
// hands to the provider: the looks that have a file. Nothing here knows which
// mode was captured in which accent — the directory listing says so.
const everything = new Set(MODES.flatMap((mode) => ACCENTS.map((accent) => variantKey(mode, accent))));
const darkOnly = new Set(ACCENTS.map((accent) => variantKey('dark', accent)).concat(['light-volt']));

describe('which accents exist', () => {
  it('follows the set it is given, in both modes', () => {
    for (const accent of ACCENTS) {
      expect(accentExists(everything, 'dark', accent)).toBe(true);
      expect(accentExists(everything, 'light', accent)).toBe(true);
      expect(accentExists(darkOnly, 'dark', accent)).toBe(true);
      expect(accentExists(darkOnly, 'light', accent)).toBe(accent === DEFAULT_ACCENT);
    }
    expect(DEFAULT_ACCENT).toBe('volt');
  });

  it('says no to everything when the pipeline has run for nothing', () => {
    for (const mode of MODES) {
      for (const accent of ACCENTS) expect(accentExists(NO_LOOKS, mode, accent)).toBe(false);
    }
  });
});

describe('the look the screenshots show', () => {
  it('follows a light site when nobody has picked a mode', () => {
    expect(resolveLook({ site: 'light', available: everything })).toEqual({
      mode: 'light',
      accent: 'volt',
      key: 'light-volt',
    });
  });

  it('follows a dark site, keeping the chosen accent', () => {
    expect(resolveLook({ site: 'dark', accent: 'ember', available: everything })).toEqual({
      mode: 'dark',
      accent: 'ember',
      key: 'dark-ember',
    });
  });

  it('keeps the chosen accent in light too once the files are there', () => {
    expect(resolveLook({ site: 'light', accent: 'ember', available: everything }).key).toBe('light-ember');
  });

  it('falls back to volt in a mode the accent was never captured in', () => {
    const chosen = 'ember';
    expect(resolveLook({ site: 'light', accent: chosen, available: darkOnly })).toEqual({
      mode: 'light',
      accent: 'volt',
      key: 'light-volt',
    });
    // The switcher keeps holding `chosen`, so dark brings it straight back.
    expect(resolveLook({ site: 'dark', accent: chosen, available: darkOnly }).key).toBe('dark-ember');
  });

  it('lets an explicit pick beat the site theme, both ways', () => {
    expect(resolveLook({ site: 'light', picked: 'dark', accent: 'berry', available: everything }).key).toBe(
      'dark-berry',
    );
    expect(resolveLook({ site: 'dark', picked: 'light', accent: 'berry', available: everything }).key).toBe(
      'light-berry',
    );
    expect(resolveLook({ site: 'dark', picked: 'light', accent: 'berry', available: darkOnly }).key).toBe(
      'light-volt',
    );
  });

  it('is the site theme again for every mode once no pick is held', () => {
    for (const site of MODES) {
      expect(resolveLook({ site, picked: null, available: everything }).mode).toBe(site);
    }
  });

  it('renders the app default where no availability is known, as off the landing page', () => {
    expect(resolveLook({ site: DEFAULT_MODE }).key).toBe(`${DEFAULT_MODE}-${DEFAULT_ACCENT}`);
    expect(resolveLook({ site: 'light', accent: 'berry' }).key).toBe('light-volt');
    expect(DEFAULT_MODE).toBe('dark');
  });
});
