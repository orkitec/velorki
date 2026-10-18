'use client';
// SPDX-License-Identifier: AGPL-3.0-only
// System / Light / Dark, next to the locale switcher: three buttons from `md`,
// and below it one button that cycles the same three states. The choice lives
// in the reader's own browser and is applied by `data-theme` on <html>, which
// globals.css reads; `ThemeScript` in the document puts the stored one back
// before the first paint, so there is no flash of the wrong palette.
import { useSyncExternalStore } from 'react';
import { useTranslations } from 'next-intl';
import {
  DEFAULT_THEME,
  THEMES,
  THEME_STORAGE_KEY,
  nextTheme,
  resolveTheme,
  themeAttribute,
  type Theme,
} from '@/site/theme';
import { DarkThemeIcon, LightThemeIcon, SystemThemeIcon } from './Icons';

const ICONS = {
  system: SystemThemeIcon,
  light: LightThemeIcon,
  dark: DarkThemeIcon,
} as const;

// The stored choice read as an external store: the server renders System, and
// React swaps in what the browser actually holds after hydration, without the
// mismatch a state-in-an-effect would warn about. `storage` covers the reader's
// other tabs; this tab's own writes are announced here.
const listeners = new Set<() => void>();

function subscribe(onChange: () => void) {
  listeners.add(onChange);
  window.addEventListener('storage', onChange);
  return () => {
    listeners.delete(onChange);
    window.removeEventListener('storage', onChange);
  };
}

function stored(): Theme {
  try {
    return resolveTheme(window.localStorage.getItem(THEME_STORAGE_KEY));
  } catch {
    // A browser with site data switched off: System, and nowhere to remember.
    return DEFAULT_THEME;
  }
}

function remember(theme: Theme) {
  const attribute = themeAttribute(theme);
  if (attribute === null) document.documentElement.removeAttribute('data-theme');
  else document.documentElement.setAttribute('data-theme', attribute);
  try {
    if (theme === DEFAULT_THEME) window.localStorage.removeItem(THEME_STORAGE_KEY);
    else window.localStorage.setItem(THEME_STORAGE_KEY, theme);
  } catch {
    // Nothing to remember it in; the page still switches for this visit.
  }
  for (const onChange of listeners) onChange();
}

export function ThemeSwitcher() {
  const t = useTranslations('theme');
  const theme = useSyncExternalStore(subscribe, stored, () => DEFAULT_THEME);
  const Current = ICONS[theme];
  const next = nextTheme(theme);

  return (
    <>
      {/* Below `md` the three buttons would push the header past the narrowest
          phone, so there the switch is one 44 px button that cycles. The icon
          shows where it stands; the label has to say the rest. */}
      <button
        type="button"
        aria-label={t('cycle', { current: t(theme), next: t(next) })}
        onClick={() => {
          remember(next);
        }}
        className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full border border-line-soft text-muted transition-colors hover:text-fg md:hidden"
      >
        <Current width={18} height={18} />
      </button>

      <div
        role="group"
        aria-label={t('label')}
        className="hidden items-center rounded-full border border-line-soft p-0.5 md:flex"
      >
        {THEMES.map((value) => {
          const Glyph = ICONS[value];
          const active = value === theme;
          return (
            <button
              key={value}
              type="button"
              aria-pressed={active}
              title={t(value)}
              onClick={() => {
                remember(value);
              }}
              className={`rounded-full p-1.5 transition-colors ${
                active ? 'bg-accent text-on-accent' : 'text-muted hover:text-fg'
              }`}
            >
              <Glyph width={16} height={16} />
              <span className="sr-only">{t(value)}</span>
            </button>
          );
        })}
      </div>
    </>
  );
}
