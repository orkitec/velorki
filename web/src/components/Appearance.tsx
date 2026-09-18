'use client';
// SPDX-License-Identifier: AGPL-3.0-only
// The one piece of state the site has: which of the app's looks the feature
// tour is showing. It starts from the site's own palette — somebody reading a
// light page sees the app in light — and follows it until they pick a side in
// the switcher, which then wins for the rest of the page view. It colours the
// surrounding section through data-attributes (see globals.css) and picks the
// screenshot every <PhoneFrame> renders.
import { createContext, useContext, useMemo, useState, useSyncExternalStore, type ReactNode } from 'react';
import { useTranslations } from 'next-intl';
import { accentExists, resolveLook, type Look } from '@/site/appearance';
import { ACCENTS, DEFAULT_ACCENT, DEFAULT_MODE, MODES, type Accent, type Mode } from '@/site/screenshots';
import { paintedTheme } from '@/site/theme';

// The palette the site is painted in, read as an external store: `data-theme`
// on <html> — put there by the header's switch, or by ThemeScript before the
// first paint — and `prefers-color-scheme` for everyone still on System. The
// same `useSyncExternalStore` shape as ThemeSwitcher, so the value is read
// synchronously on the client and no state-in-an-effect can warn about a
// mismatch. One observer and one media query serve every frame on the page.
const modeListeners = new Set<() => void>();
let watch: { observer: MutationObserver; media: MediaQueryList } | null = null;

function announce() {
  for (const onChange of modeListeners) onChange();
}

function subscribeSiteMode(onChange: () => void) {
  modeListeners.add(onChange);
  if (!watch) {
    const observer = new MutationObserver(announce);
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    media.addEventListener('change', announce);
    watch = { observer, media };
  }
  return () => {
    modeListeners.delete(onChange);
    if (modeListeners.size === 0 && watch) {
      watch.observer.disconnect();
      watch.media.removeEventListener('change', announce);
      watch = null;
    }
  };
}

function siteMode(): Mode {
  return paintedTheme(
    document.documentElement.getAttribute('data-theme'),
    window.matchMedia('(prefers-color-scheme: dark)').matches,
  );
}

/**
 * The palette the page itself is in. The server knows nothing about it and
 * renders the app's own default look; the client reads the real one during
 * hydration, so the swap costs at most the one frame it takes React to commit.
 */
function useSiteMode(): Mode {
  return useSyncExternalStore(subscribeSiteMode, siteMode, () => DEFAULT_MODE);
}

/** What the switcher holds: nothing at all until somebody touches it. */
interface AppearanceChoice {
  picked: Mode | null;
  accent: Accent;
  pick: (mode: Mode) => void;
  choose: (accent: Accent) => void;
}

const AppearanceContext = createContext<AppearanceChoice | null>(null);

export interface Appearance {
  /** The variant the frames render: the resolved mode and an accent that exists in it. */
  look: Look;
  /** The accent that was chosen, kept while light has no shot for it. */
  accent: Accent;
  setMode: (mode: Mode) => void;
  setAccent: (accent: Accent) => void;
}

const IGNORE = () => undefined;

/**
 * Off the landing page there is no switcher and no provider — `/plus` and
 * `/download` show a single frame — and the look is then the site's palette
 * with the default accent.
 */
export function useAppearance(): Appearance {
  const choice = useContext(AppearanceContext);
  const site = useSiteMode();
  const picked = choice?.picked ?? null;
  const accent = choice?.accent ?? DEFAULT_ACCENT;
  const setMode = choice?.pick ?? IGNORE;
  const setAccent = choice?.choose ?? IGNORE;
  return useMemo(
    () => ({ look: resolveLook({ site, picked, accent }), accent, setMode, setAccent }),
    [site, picked, accent, setMode, setAccent],
  );
}

/**
 * Wraps the feature tour. The server renders `children` — only the provider
 * and the switcher are client components, so the sections stay server markup.
 */
export function AppearanceProvider({ children }: { children: ReactNode }) {
  const [picked, setPicked] = useState<Mode | null>(null);
  const [accent, setAccent] = useState<Accent>(DEFAULT_ACCENT);
  const choice = useMemo<AppearanceChoice>(
    () => ({ picked, accent, pick: setPicked, choose: setAccent }),
    [picked, accent],
  );
  return (
    <AppearanceContext.Provider value={choice}>
      <AppearanceSection>{children}</AppearanceSection>
    </AppearanceContext.Provider>
  );
}

/** Inside the provider, so the section's own colours follow the resolved look. */
function AppearanceSection({ children }: { children: ReactNode }) {
  const { look } = useAppearance();
  return (
    <div data-mode={look.mode} data-accent={look.accent}>
      {children}
    </div>
  );
}

const ACCENT_SWATCH: Record<Accent, { dark: string; light: string }> = {
  volt: { dark: '#C8F542', light: '#3F7A00' },
  ember: { dark: '#FF7A45', light: '#C63D12' },
  glacier: { dark: '#5CD6FF', light: '#0071A6' },
  berry: { dark: '#FF66B0', light: '#B8155F' },
  forest: { dark: '#3FBF8A', light: '#1B7F5A' },
};

/** The light/dark and accent controls above the feature tour. */
export function AppearanceSwitcher() {
  const t = useTranslations('appearance');
  const { look, setMode, setAccent } = useAppearance();
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
              aria-pressed={look.mode === value}
              onClick={() => {
                setMode(value);
              }}
              className={`rounded-full px-4 py-1.5 text-sm font-bold transition-colors ${
                look.mode === value ? 'bg-accent text-on-accent' : 'text-muted hover:text-fg'
              }`}
            >
              {t(value)}
            </button>
          ))}
        </div>
      </fieldset>
      <fieldset className="flex items-center gap-3">
        <legend className="sr-only">{t('accent')}</legend>
        {/* Five chips are wider than a phone: they wrap rather than push the
            page sideways. */}
        <div className="flex flex-wrap gap-2">
          {ACCENTS.map((value) => {
            // Light is captured in Volt only. `aria-disabled` rather than the
            // `disabled` attribute: a disabled control receives no pointer
            // events, so the browser would never show the `title` that says
            // why the chip is off.
            const exists = accentExists(look.mode, value);
            return (
              <button
                key={value}
                type="button"
                aria-pressed={look.accent === value}
                aria-disabled={!exists}
                onClick={() => {
                  if (exists) setAccent(value);
                }}
                title={exists ? t(value) : t('lightVoltOnly')}
                className={`flex h-9 items-center gap-2 rounded-full border px-3 text-sm font-bold transition-colors ${
                  look.accent === value ? 'border-accent text-fg' : 'border-line text-muted hover:text-fg'
                } ${exists ? '' : 'cursor-not-allowed opacity-45 hover:text-muted'}`}
              >
                <span
                  aria-hidden="true"
                  className="h-3.5 w-3.5 rounded-full"
                  style={{ background: ACCENT_SWATCH[value][look.mode] }}
                />
                {t(value)}
              </button>
            );
          })}
        </div>
      </fieldset>
      <p className="sr-only">{t('hint')}</p>
    </div>
  );
}
