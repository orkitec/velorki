'use client';
// SPDX-License-Identifier: AGPL-3.0-only
// The one piece of state the site has: which of the app's looks the feature
// tour is showing. It colours the surrounding section through data-attributes
// (see globals.css) and picks the screenshot every <PhoneFrame> renders.
import { createContext, useContext, useMemo, useState, type ReactNode } from 'react';
import { useTranslations } from 'next-intl';
import { ACCENTS, DEFAULT_ACCENT, DEFAULT_MODE, MODES, type Accent, type Mode } from '@/site/screenshots';

interface Appearance {
  mode: Mode;
  accent: Accent;
  setMode: (mode: Mode) => void;
  setAccent: (accent: Accent) => void;
}

const AppearanceContext = createContext<Appearance>({
  mode: DEFAULT_MODE,
  accent: DEFAULT_ACCENT,
  setMode: () => undefined,
  setAccent: () => undefined,
});

export function useAppearance(): Appearance {
  return useContext(AppearanceContext);
}

/**
 * Wraps the feature tour. The server renders `children` — only the provider
 * and the switcher are client components, so the sections stay server markup.
 */
export function AppearanceProvider({ children }: { children: ReactNode }) {
  const [mode, setMode] = useState<Mode>(DEFAULT_MODE);
  const [accent, setAccent] = useState<Accent>(DEFAULT_ACCENT);
  const value = useMemo(() => ({ mode, accent, setMode, setAccent }), [mode, accent]);
  return (
    <AppearanceContext.Provider value={value}>
      <div data-mode={mode} data-accent={accent}>
        {children}
      </div>
    </AppearanceContext.Provider>
  );
}

const ACCENT_SWATCH: Record<Accent, { dark: string; light: string }> = {
  volt: { dark: '#C8F542', light: '#3F7A00' },
  ember: { dark: '#FF7A45', light: '#C63D12' },
  glacier: { dark: '#5CD6FF', light: '#0071A6' },
  berry: { dark: '#FF66B0', light: '#B8155F' },
};

/** The light/dark and accent controls above the feature tour. */
export function AppearanceSwitcher() {
  const t = useTranslations('appearance');
  const { mode, accent, setMode, setAccent } = useAppearance();
  return (
    <div className="flex flex-wrap items-center gap-x-8 gap-y-4">
      <fieldset className="flex items-center gap-3">
        <legend className="sr-only">{t('mode')}</legend>
        <span className="overline" aria-hidden="true">
          {t('legend')}
        </span>
        <div className="flex rounded-full border border-line bg-panel p-1">
          {MODES.map((value) => (
            <button
              key={value}
              type="button"
              aria-pressed={mode === value}
              onClick={() => {
                setMode(value);
              }}
              className={`rounded-full px-4 py-1.5 text-sm font-bold transition-colors ${
                mode === value ? 'bg-accent text-on-accent' : 'text-muted hover:text-fg'
              }`}
            >
              {t(value)}
            </button>
          ))}
        </div>
      </fieldset>
      <fieldset className="flex items-center gap-3">
        <legend className="sr-only">{t('accent')}</legend>
        <div className="flex gap-2">
          {ACCENTS.map((value) => (
            <button
              key={value}
              type="button"
              aria-pressed={accent === value}
              onClick={() => {
                setAccent(value);
              }}
              title={t(value)}
              className={`flex h-9 items-center gap-2 rounded-full border px-3 text-sm font-bold transition-colors ${
                accent === value ? 'border-accent text-fg' : 'border-line text-muted hover:text-fg'
              }`}
            >
              <span
                aria-hidden="true"
                className="h-3.5 w-3.5 rounded-full"
                style={{ background: mode === 'dark' ? ACCENT_SWATCH[value].dark : ACCENT_SWATCH[value].light }}
              />
              {t(value)}
            </button>
          ))}
        </div>
      </fieldset>
      <p className="sr-only">{t('hint')}</p>
    </div>
  );
}
