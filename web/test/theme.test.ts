// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import { DEFAULT_THEME, THEMES, THEME_STORAGE_KEY, resolveTheme, themeAttribute } from '@/site/theme';

describe('theme choice', () => {
  it('keeps the three states it writes', () => {
    for (const theme of THEMES) {
      expect(resolveTheme(theme)).toBe(theme);
    }
  });

  it('falls back to System for anything it did not write', () => {
    for (const stored of [null, undefined, '', 'Dark', 'auto', 'nope', '  dark  ']) {
      expect(resolveTheme(stored)).toBe(DEFAULT_THEME);
    }
    expect(DEFAULT_THEME).toBe('system');
  });

  it('puts the attribute on <html> for a forced palette only', () => {
    expect(themeAttribute('system')).toBeNull();
    expect(themeAttribute('light')).toBe('light');
    expect(themeAttribute('dark')).toBe('dark');
  });

  it('remembers the choice under a namespaced key', () => {
    expect(THEME_STORAGE_KEY).toBe('velorki.theme');
  });
});
