// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import { accentExists, resolveLook } from '@/site/appearance';
import { ACCENTS, DEFAULT_ACCENT, DEFAULT_MODE, MODES } from '@/site/screenshots';
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

describe('which accents exist', () => {
  it('has every accent in dark and only the default one in light', () => {
    for (const accent of ACCENTS) {
      expect(accentExists('dark', accent)).toBe(true);
      expect(accentExists('light', accent)).toBe(accent === DEFAULT_ACCENT);
    }
    expect(DEFAULT_ACCENT).toBe('volt');
  });
});

describe('the look the screenshots show', () => {
  it('follows a light site when nobody has picked a mode', () => {
    expect(resolveLook({ site: 'light' })).toEqual({ mode: 'light', accent: 'volt', key: 'light-volt' });
  });

  it('follows a dark site, keeping the chosen accent', () => {
    expect(resolveLook({ site: 'dark', accent: 'ember' })).toEqual({
      mode: 'dark',
      accent: 'ember',
      key: 'dark-ember',
    });
  });

  it('shows volt on a light site but does not forget the accent', () => {
    const chosen = 'ember';
    expect(resolveLook({ site: 'light', accent: chosen })).toEqual({
      mode: 'light',
      accent: 'volt',
      key: 'light-volt',
    });
    // The switcher keeps holding `chosen`, so dark brings it straight back.
    expect(resolveLook({ site: 'dark', accent: chosen }).key).toBe('dark-ember');
  });

  it('lets an explicit pick beat the site theme, both ways', () => {
    expect(resolveLook({ site: 'light', picked: 'dark', accent: 'berry' }).key).toBe('dark-berry');
    expect(resolveLook({ site: 'dark', picked: 'light', accent: 'berry' }).key).toBe('light-volt');
  });

  it('is the site theme again for every mode once no pick is held', () => {
    for (const site of MODES) {
      expect(resolveLook({ site, picked: null }).mode).toBe(site);
    }
  });

  it('renders the app default on the server, where no site theme is known', () => {
    expect(resolveLook({ site: DEFAULT_MODE }).key).toBe(`${DEFAULT_MODE}-${DEFAULT_ACCENT}`);
    expect(DEFAULT_MODE).toBe('dark');
  });
});
