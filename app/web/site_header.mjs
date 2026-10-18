// SPDX-License-Identifier: AGPL-3.0-only
// The website's header (web/src/components/SiteHeader.tsx with HeaderMenu,
// ThemeSwitcher and LocaleSwitcherMenu) in plain DOM, for the pages of the
// web build: above the planner, and on the download page phones get. One
// copy for both; app/web_test/site_header.test.mjs holds its links and words
// to the site's.
//
// The theme and language switches are the planner's own settings: they read
// and write what the app keeps (shared_preferences on the web is
// localStorage, 'flutter.' before the key, the value JSON), and the app and
// the header tell each other of a change with two DOM events (see
// lib/app/web/header_bridge.dart): `velorki-header` from here when the
// reader picks something, `velorki-app-settings` from the app when its own
// settings change it.

export const SITE_URL = 'https://velorki.com';
export const GITHUB_URL = 'https://github.com/orkitec/velorki';

/** The site's languages, which are the app's (lib/l10n/app_*.arb). */
export const LANGS = ['en', 'de', 'es', 'fr', 'it', 'nl'];

/** What each language calls itself (web/src/site/locales.ts). */
export const LOCALE_NAMES = {
  en: 'English',
  de: 'Deutsch',
  es: 'Español',
  fr: 'Français',
  it: 'Italiano',
  nl: 'Nederlands',
};

/** The site's System / Light / Dark (web/src/site/theme.ts). */
export const THEMES = ['system', 'light', 'dark'];

/**
 * The header's wording, the website's own (web/messages/<lang>.json: `nav`,
 * `theme`, `localeSwitcher.label`), held to it by the test.
 */
export const HEADER_STRINGS = {
  en: {
    home: 'Velorki home',
    primary: 'Main',
    features: 'Features',
    docs: 'Docs',
    plus: 'Plus',
    github: 'GitHub',
    getApp: 'Get the app',
    menu: 'Menu',
    theme: 'Theme',
    system: 'System',
    light: 'Light',
    dark: 'Dark',
    cycle: 'Theme: {current}. Switch to {next}.',
    language: 'Language',
  },
  de: {
    home: 'Velorki Startseite',
    primary: 'Haupt',
    features: 'Funktionen',
    docs: 'Doku',
    plus: 'Plus',
    github: 'GitHub',
    getApp: 'App holen',
    menu: 'Menü',
    theme: 'Design',
    system: 'System',
    light: 'Hell',
    dark: 'Dunkel',
    cycle: 'Design: {current}. Zu {next} wechseln.',
    language: 'Sprache',
  },
  es: {
    home: 'Inicio de Velorki',
    primary: 'Principal',
    features: 'Funciones',
    docs: 'Ayuda',
    plus: 'Plus',
    github: 'GitHub',
    getApp: 'Consigue la app',
    menu: 'Menú',
    theme: 'Tema',
    system: 'Sistema',
    light: 'Claro',
    dark: 'Oscuro',
    cycle: 'Tema: {current}. Cambiar a {next}.',
    language: 'Idioma',
  },
  fr: {
    home: 'Accueil Velorki',
    primary: 'Principal',
    features: 'Fonctions',
    docs: 'Guide',
    plus: 'Plus',
    github: 'GitHub',
    getApp: 'Obtenir l’app',
    menu: 'Ouvrir le menu',
    theme: 'Thème',
    system: 'Système',
    light: 'Clair',
    dark: 'Sombre',
    cycle: 'Thème : {current}. Passer à {next}.', // a no-break space before the colon, as the site writes it
    language: 'Langue',
  },
  it: {
    home: 'Pagina iniziale di Velorki',
    primary: 'Principale',
    features: 'Funzionalità',
    docs: 'Guida',
    plus: 'Plus',
    github: 'GitHub',
    getApp: "Scarica l'app",
    menu: 'Menù',
    theme: 'Tema',
    system: 'Sistema',
    light: 'Chiaro',
    dark: 'Scuro',
    cycle: 'Tema: {current}. Passa a {next}.',
    language: 'Lingua',
  },
  nl: {
    home: 'Velorki-startpagina',
    primary: 'Hoofdmenu',
    features: 'Functies',
    docs: 'Handleiding',
    plus: 'Plus',
    github: 'GitHub',
    getApp: 'Download de app',
    menu: 'Menu',
    theme: 'Thema',
    system: 'Systeem',
    light: 'Licht',
    dark: 'Donker',
    cycle: 'Thema: {current}. Overschakelen naar {next}.',
    language: 'Taal',
  },
};

/** The site's NAV (SiteHeader.tsx), in its order. */
export const NAV = [
  { key: 'features', href: '/#features' },
  { key: 'docs', href: '/docs' },
  { key: 'plus', href: '/plus' },
];

/** The first of the reader's languages the site is written in, else English. */
export function pickLanguage(languages) {
  for (const tag of languages ?? []) {
    const lang = String(tag).toLowerCase().split(/[-_]/)[0];
    if (LANGS.includes(lang)) return lang;
  }
  return 'en';
}

/** The website's localized URL for `path`; English is unprefixed, as on the site. */
export function siteUrl(lang, path = '/') {
  if (lang === 'en') return `${SITE_URL}${path}`;
  return path === '/' ? `${SITE_URL}/${lang}` : `${SITE_URL}/${lang}${path}`;
}

// ---------------------------------------------------------------- settings

/** Where the app keeps its theme and its language (appearance_controller.dart,
    language_controller.dart), as shared_preferences writes them on the web. */
export const THEME_KEY = 'flutter.appearance.mode';
export const LOCALE_KEY = 'flutter.language.locale';

function read(storage, key) {
  try {
    const raw = storage?.getItem(key);
    return raw == null ? null : JSON.parse(raw);
  } catch {
    return null;
  }
}

function write(storage, key, value) {
  try {
    if (value == null) storage?.removeItem(key);
    else storage?.setItem(key, JSON.stringify(value));
  } catch {
    // No site data: the switch still works for this visit.
  }
}

/** The theme the app keeps, System when nothing (or nothing known) is kept. */
export function storedTheme(storage) {
  const value = read(storage, THEME_KEY);
  return THEMES.includes(value) ? value : 'system';
}

/** The language the app keeps, or `null` while it follows the browser. */
export function storedLocale(storage) {
  const value = read(storage, LOCALE_KEY);
  const lang = typeof value === 'string' ? value.toLowerCase().split(/[-_]/)[0] : null;
  return LANGS.includes(lang) ? lang : null;
}

/** Keeps `theme` where the app keeps it: nothing for System, as the app does. */
export function storeTheme(storage, theme) {
  write(storage, THEME_KEY, theme === 'system' ? null : theme);
}

export function storeLocale(storage, lang) {
  write(storage, LOCALE_KEY, lang);
}

/** The state after a tap of the compact switch: System → Light → Dark → System. */
export function nextTheme(theme) {
  return THEMES[(THEMES.indexOf(theme) + 1) % THEMES.length] ?? 'system';
}

// -------------------------------------------------------------------- DOM

const SVG_NS = 'http://www.w3.org/2000/svg';

export function el(document, tag, attrs = {}, children = []) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v !== undefined && v !== null) node.setAttribute(k, v);
  }
  for (const child of children) {
    if (child == null) continue;
    node.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
  }
  return node;
}

export function svg(document, tag, attrs = {}, children = []) {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  for (const child of children) node.appendChild(child);
  return node;
}

/** web/public/icon.svg, coloured by --tile and --glyph. */
export function appIcon(document, size) {
  const rings = [
    [313.71, 324.73],
    [710.29, 324.73],
    [512, 699.27],
  ];
  return svg(
    document,
    'svg',
    { viewBox: '0 0 1024 1024', width: size, height: size, 'aria-hidden': 'true', focusable: 'false' },
    [
      svg(document, 'rect', { width: 1024, height: 1024, rx: 225.28, class: 'vg-tile' }),
      svg(document, 'path', {
        d: 'M313.71 324.73 Q 351.35 542.29 512 699.27 Q 672.65 542.29 710.29 324.73',
        class: 'vg-route',
        'stroke-width': 66.1,
        'stroke-linecap': 'round',
        'stroke-linejoin': 'round',
      }),
      ...rings.map(([cx, cy]) => svg(document, 'circle', { cx, cy, r: 95.47, class: 'vg-glyph' })),
      ...rings.map(([cx, cy]) => svg(document, 'circle', { cx, cy, r: 40.39, class: 'vg-tile' })),
    ],
  );
}

// web/src/components/Icons.tsx: the header's glyphs, 24 × 24.
export const GLYPHS = {
  github: [
    [
      'path',
      {
        fill: 'currentColor',
        d: 'M12 .5a11.5 11.5 0 0 0-3.64 22.41c.58.1.79-.25.79-.56v-2c-3.2.7-3.88-1.37-3.88-1.37-.53-1.35-1.3-1.7-1.3-1.7-1.05-.72.08-.71.08-.71 1.17.08 1.78 1.2 1.78 1.2 1.03 1.78 2.7 1.27 3.36.97.1-.75.4-1.27.73-1.56-2.56-.29-5.25-1.28-5.25-5.7 0-1.26.45-2.29 1.19-3.1-.12-.29-.52-1.46.11-3.05 0 0 .97-.31 3.18 1.18a11 11 0 0 1 5.8 0c2.2-1.5 3.17-1.18 3.17-1.18.63 1.59.24 2.76.12 3.05.74.81 1.18 1.84 1.18 3.1 0 4.43-2.69 5.4-5.26 5.69.41.36.78 1.06.78 2.14v3.17c0 .31.21.67.8.56A11.5 11.5 0 0 0 12 .5Z',
      },
    ],
  ],
  globe: [
    ['circle', { cx: 12, cy: 12, r: 9, fill: 'none', stroke: 'currentColor', 'stroke-width': 1.8 }],
    [
      'path',
      {
        fill: 'none',
        stroke: 'currentColor',
        'stroke-width': 1.8,
        d: 'M3 12h18M12 3c2.5 2.6 2.5 15.4 0 18M12 3c-2.5 2.6-2.5 15.4 0 18',
      },
    ],
  ],
  chevron: [
    [
      'path',
      {
        fill: 'none',
        stroke: 'currentColor',
        'stroke-width': 2,
        'stroke-linecap': 'round',
        'stroke-linejoin': 'round',
        d: 'm6 9.5 6 6 6-6',
      },
    ],
  ],
  system: [
    ['rect', { x: 3, y: 4.5, width: 18, height: 12.5, rx: 2, fill: 'none', stroke: 'currentColor', 'stroke-width': 1.8 }],
    ['path', { fill: 'none', stroke: 'currentColor', 'stroke-width': 1.8, 'stroke-linecap': 'round', d: 'M9 20.5h6' }],
  ],
  light: [
    ['circle', { cx: 12, cy: 12, r: 4, fill: 'none', stroke: 'currentColor', 'stroke-width': 1.8 }],
    [
      'path',
      {
        fill: 'none',
        stroke: 'currentColor',
        'stroke-width': 1.8,
        'stroke-linecap': 'round',
        d: 'M12 3v2m0 14v2M3 12h2m14 0h2M5.6 5.6 7 7m10 10 1.4 1.4M18.4 5.6 17 7M7 17l-1.4 1.4',
      },
    ],
  ],
  dark: [
    [
      'path',
      {
        fill: 'none',
        stroke: 'currentColor',
        'stroke-width': 1.8,
        'stroke-linejoin': 'round',
        d: 'M20 14.2A8.2 8.2 0 0 1 9.8 4a8.2 8.2 0 1 0 10.2 10.2Z',
      },
    ],
  ],
  menu: [
    ['path', { fill: 'none', stroke: 'currentColor', 'stroke-width': 2, 'stroke-linecap': 'round', d: 'M4 7h16M4 12h16M4 17h16' }],
  ],
  close: [
    ['path', { fill: 'none', stroke: 'currentColor', 'stroke-width': 2, 'stroke-linecap': 'round', d: 'm6 6 12 12M18 6 6 18' }],
  ],
};

export function glyph(document, name, size, cls) {
  return svg(
    document,
    'svg',
    { viewBox: '0 0 24 24', width: size, height: size, 'aria-hidden': 'true', focusable: 'false', ...(cls ? { class: cls } : {}) },
    GLYPHS[name].map(([tag, attrs]) => svg(document, tag, attrs)),
  );
}

/**
 * The website's tokens (web/src/app/globals.css: the palettes, `data-theme`
 * over `prefers-color-scheme`, `.shell`, `.btn`) and the header's Tailwind
 * classes written out, as they render: `.btn` is unlayered CSS on the site
 * and beats the pill's `px-4 text-sm`, so the pill keeps `.btn`'s padding and
 * size here too. Breakpoints as Tailwind's: sm 640, md 768, lg 1024.
 */
export const HEADER_CSS = `
@font-face{font-family:Manrope;src:url(fonts/Manrope-latin.woff2) format('woff2');font-weight:400 700;font-display:swap}
@font-face{font-family:'Barlow Condensed';src:url(fonts/BarlowCondensed-Bold-latin.woff2) format('woff2');font-weight:700;font-display:swap}
:root{color-scheme:light dark;--canvas:#f5f6f3;--panel:#fff;--fg:#14171a;--muted:#5b636c;--line:#d7dbd5;--line-soft:#e4e7e2;--accent:#3f7a00;--on-accent:#fff;--accent-soft:rgb(63 122 0/.12);--accent-10:rgb(63 122 0/.1);--tile:#3f7a00;--glyph:#fff}
:root[data-theme=light]{color-scheme:light}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){--canvas:#0e1115;--panel:#1b1f26;--fg:#f1f3f5;--muted:#aab2bc;--line:#2c333c;--line-soft:#232930;--accent:#c8f542;--on-accent:#0e1115;--accent-soft:rgb(200 245 66/.14);--accent-10:rgb(200 245 66/.1);--tile:#c8f542;--glyph:#0e1115}}
:root[data-theme=dark]{color-scheme:dark;--canvas:#0e1115;--panel:#1b1f26;--fg:#f1f3f5;--muted:#aab2bc;--line:#2c333c;--line-soft:#232930;--accent:#c8f542;--on-accent:#0e1115;--accent-soft:rgb(200 245 66/.14);--accent-10:rgb(200 245 66/.1);--tile:#c8f542;--glyph:#0e1115}
html,body{margin:0;background:var(--canvas)}
.vg-tile{fill:var(--tile)}.vg-glyph{fill:var(--glyph)}.vg-route{fill:none;stroke:var(--glyph)}
.vh{position:sticky;top:0;z-index:50;overflow-x:clip;border-bottom:1px solid var(--line-soft);background:color-mix(in srgb,var(--canvas) 85%,transparent);-webkit-backdrop-filter:blur(16px);backdrop-filter:blur(16px);padding-top:env(safe-area-inset-top,0px);color:var(--fg);font:500 1rem/1.55 Manrope,ui-sans-serif,system-ui,-apple-system,sans-serif;-webkit-font-smoothing:antialiased;-webkit-text-size-adjust:100%}
.vh *,.vh *::before,.vh *::after{box-sizing:border-box}
.vh a{color:inherit;text-decoration:none}
.vh a.vh-link,.vh-panel nav a{color:var(--muted)}
.vh button{font:inherit;color:inherit;background:none;border:0;margin:0;cursor:pointer}
.vh :focus-visible{outline:2px solid color-mix(in srgb,var(--fg) 55%,transparent);outline-offset:2px}
.vh-shell{width:100%;max-width:76rem;margin-inline:auto;padding-inline:max(1.25rem,env(safe-area-inset-left,0px)) max(1.25rem,env(safe-area-inset-right,0px))}
.vh-bar{display:flex;height:4rem;align-items:center;gap:.5rem}
.vh-brand{display:flex;flex-shrink:0;align-items:center;gap:.5rem}
.vh-word{font-family:'Barlow Condensed',ui-sans-serif,sans-serif;font-size:1.25rem;line-height:1;font-weight:700;letter-spacing:-.025em;color:var(--fg)}
.vh-nav{margin-left:auto;display:none;align-items:center;gap:.25rem}
.vh-link{border-radius:999px;padding:.5rem;font-size:.875rem;line-height:1.25rem;font-weight:700;color:var(--muted);transition:color .15s,background-color .15s}
.vh a.vh-link:hover{background:var(--accent-10);color:var(--fg)}
.vh-gh{display:flex;align-items:center;gap:.375rem}
.vh a.vh-gh:hover{background:none}
.vh-sr{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
.vh-right{margin-left:auto;display:flex;align-items:center;gap:.375rem}
.vh-round{display:flex;height:2.75rem;width:2.75rem;flex-shrink:0;align-items:center;justify-content:center;border-radius:999px;border:1px solid var(--line-soft)!important;color:var(--muted)!important;transition:color .15s}
.vh-round:hover{color:var(--fg)!important}
.vh-themes{display:none;align-items:center;border-radius:999px;border:1px solid var(--line-soft);padding:.125rem}
.vh-themes button{display:flex;border-radius:999px;padding:.375rem;color:var(--muted);transition:color .15s,background-color .15s}
.vh-themes button:hover{color:var(--fg)}
.vh-themes button[aria-pressed=true]{background:var(--accent);color:var(--on-accent)}
.vh-loc{position:relative}
.vh details>summary{list-style:none}
.vh details>summary::-webkit-details-marker{display:none}
.vh-loc summary{display:flex;height:2.75rem;cursor:pointer;align-items:center;gap:.25rem;border-radius:999px;border:1px solid var(--line-soft);padding-inline:.625rem;font-size:.75rem;line-height:1rem;font-weight:700;letter-spacing:.025em;color:var(--muted);transition:color .15s}
.vh-loc summary:hover{color:var(--fg)}
.vh-loc .vh-name,.vh-loc .vh-chev{display:none}
.vh-loc details[open] .vh-chev{transform:rotate(180deg)}
.vh-chev{transition:transform .15s}
.vh-locs{position:absolute;right:0;z-index:50;margin:.25rem 0 0;min-width:10rem;list-style:none;border-radius:1rem;border:1px solid var(--line-soft);background:var(--panel);padding:.25rem;box-shadow:0 10px 15px -3px rgb(0 0 0/.1),0 4px 6px -4px rgb(0 0 0/.1)}
.vh-locs button{display:block;width:100%;text-align:left;border-radius:.75rem;padding:.5rem .75rem;font-size:.875rem;line-height:1.25rem;font-weight:700;color:var(--muted);transition:color .15s,background-color .15s}
.vh-locs button:hover{background:var(--accent-10);color:var(--fg)}
.vh-locs button[aria-current=true]{background:var(--accent);color:var(--on-accent)}
.vh-btn{display:inline-flex;align-items:center;justify-content:center;gap:.5rem;border-radius:999px;font-weight:700;border:1px solid transparent;background:var(--accent);color:var(--on-accent)!important;transition:transform .12s ease}
.vh-btn:hover{transform:translateY(-1px)}
.vh-dl{display:none}
.vh-dl .vh-btn{min-height:2.5rem;padding:0 1.5rem;font-size:.9375rem}
.vh-menu summary{cursor:pointer;color:var(--fg)!important}
.vh-menu .vh-x,.vh-menu[open] .vh-burger{display:none}
.vh-menu[open] .vh-x{display:block}
.vh-panel{position:absolute;left:0;right:0;top:100%;border-bottom:1px solid var(--line-soft);background:var(--canvas);box-shadow:0 10px 15px -3px rgb(0 0 0/.1),0 4px 6px -4px rgb(0 0 0/.1)}
.vh-panel .vh-shell{display:flex;flex-direction:column;gap:.25rem;padding-block:.75rem}
.vh-panel nav{display:flex;flex-direction:column;gap:.25rem}
.vh-panel nav a{display:flex;min-height:2.75rem;align-items:center;gap:.5rem;border-radius:1rem;padding-inline:.75rem;font-size:1rem;line-height:1.5rem;font-weight:700;color:var(--muted)}
.vh-panel .vh-btn{margin-top:.5rem;min-height:3rem;padding:0 1.5rem;font-size:.9375rem}
@media (min-width:640px){.vh-word{font-size:1.5rem}}
@media (min-width:768px){.vh-shell{padding-inline:max(2rem,env(safe-area-inset-left,0px)) max(2rem,env(safe-area-inset-right,0px))}.vh-bar{gap:.75rem}.vh-nav{display:flex}.vh-right{margin-left:0;gap:.5rem}.vh-cycle,.vh-menu{display:none!important}.vh-themes{display:flex}.vh-loc summary{height:auto;gap:.375rem;border-color:transparent;padding-block:.375rem}.vh-dl{display:block}}
@media (min-width:1024px){.vh-link{padding-inline:.75rem}.vh-gh .vh-sr{position:static;width:auto;height:auto;margin:0;overflow:visible;clip:auto;white-space:normal}.vh-loc .vh-code{display:none}.vh-loc .vh-name{display:inline}.vh-loc .vh-chev{display:block}}
`;

/**
 * Builds the header for `lang` and returns it with a way to follow a theme or
 * a language set from elsewhere. `onTheme` and `onLanguage` run when the
 * reader picks one here, after it is shown and kept.
 */
export function renderHeader(window, { lang, theme, onTheme, onLanguage }) {
  const { document } = window;
  const state = { lang, theme };
  const header = el(document, 'header', { class: 'vh', id: 'velorki-header' });

  const applyTheme = () => {
    const root = document.documentElement;
    if (state.theme === 'system') root.removeAttribute('data-theme');
    else root.setAttribute('data-theme', state.theme);
  };

  const build = () => {
    const t = HEADER_STRINGS[state.lang] ?? HEADER_STRINGS.en;
    const links = NAV.map((item) => ({ href: siteUrl(state.lang, item.href), label: t[item.key] }));
    const navLink = (link, cls) => el(document, 'a', { href: link.href, class: cls }, [link.label]);

    // The wide row: Features, Docs, Plus, GitHub.
    const nav = el(document, 'nav', { class: 'vh-nav', 'aria-label': t.primary }, [
      ...links.map((link) => navLink(link, 'vh-link')),
      el(document, 'a', { href: GITHUB_URL, rel: 'noreferrer', class: 'vh-link vh-gh' }, [
        glyph(document, 'github', 16),
        el(document, 'span', { class: 'vh-sr' }, [t.github]),
      ]),
    ]);

    // System / Light / Dark: one cycling button below md, three from md.
    const label = (name) => t[name];
    const next = nextTheme(state.theme);
    const cycle = el(
      document,
      'button',
      {
        type: 'button',
        class: 'vh-round vh-cycle',
        'aria-label': t.cycle.replace('{current}', label(state.theme)).replace('{next}', label(next)),
      },
      [glyph(document, state.theme, 18)],
    );
    cycle.addEventListener('click', () => pickTheme(next));
    const themes = el(
      document,
      'div',
      { class: 'vh-themes', role: 'group', 'aria-label': t.theme },
      THEMES.map((value) => {
        const button = el(
          document,
          'button',
          { type: 'button', 'aria-pressed': String(value === state.theme), title: label(value) },
          [glyph(document, value, 16), el(document, 'span', { class: 'vh-sr' }, [label(value)])],
        );
        button.addEventListener('click', () => pickTheme(value));
        return button;
      }),
    );

    // The languages: the globe and the code, the name from lg.
    const locales = el(
      document,
      'ul',
      { class: 'vh-locs' },
      LANGS.map((code) => {
        const button = el(
          document,
          'button',
          { type: 'button', lang: code, 'aria-current': code === state.lang ? 'true' : undefined },
          [LOCALE_NAMES[code]],
        );
        button.addEventListener('click', () => pickLanguage_(code));
        return el(document, 'li', {}, [button]);
      }),
    );
    const localeMenu = el(document, 'nav', { class: 'vh-loc', 'aria-label': t.language }, [
      el(document, 'details', {}, [
        el(document, 'summary', {}, [
          glyph(document, 'globe', 16),
          el(document, 'span', { class: 'vh-code' }, [state.lang.toUpperCase()]),
          el(document, 'span', { class: 'vh-name' }, [LOCALE_NAMES[state.lang]]),
          glyph(document, 'chevron', 14, 'vh-chev'),
        ]),
        locales,
      ]),
    ]);

    // Below md the links and the "Get the app" pill live in the menu.
    const download = siteUrl(state.lang, '/download');
    const menu = el(document, 'details', { class: 'vh-menu', 'data-header-menu': '' }, [
      el(document, 'summary', { class: 'vh-round', 'aria-label': t.menu }, [
        glyph(document, 'menu', 20, 'vh-burger'),
        glyph(document, 'close', 20, 'vh-x'),
      ]),
      el(document, 'div', { class: 'vh-panel' }, [
        el(document, 'div', { class: 'vh-shell' }, [
          el(document, 'nav', { 'aria-label': t.primary }, [
            ...links.map((link) => navLink(link)),
            el(document, 'a', { href: GITHUB_URL, rel: 'noreferrer' }, [glyph(document, 'github', 16), t.github]),
          ]),
          el(document, 'a', { href: download, class: 'vh-btn' }, [t.getApp]),
        ]),
      ]),
    ]);

    const bar = el(document, 'div', { class: 'vh-shell vh-bar' }, [
      el(document, 'a', { href: siteUrl(state.lang), 'aria-label': t.home, class: 'vh-brand' }, [
        appIcon(document, 32),
        el(document, 'span', { class: 'vh-word' }, ['Velorki']),
      ]),
      nav,
      el(document, 'div', { class: 'vh-right' }, [
        cycle,
        themes,
        localeMenu,
        el(document, 'div', { class: 'vh-dl' }, [el(document, 'a', { href: download, class: 'vh-btn' }, [t.getApp])]),
        menu,
      ]),
    ]);
    while (header.firstChild) header.removeChild(header.firstChild);
    header.appendChild(bar);
  };

  function pickTheme(value) {
    if (value === state.theme) return;
    set({ theme: value });
    onTheme?.(value);
  }

  function pickLanguage_(code) {
    for (const open of header.querySelectorAll?.('details[open]') ?? []) open.removeAttribute('open');
    if (code === state.lang) return;
    set({ lang: code });
    onLanguage?.(code);
  }

  /** Shows `theme` and `lang` as they now are, without telling anyone. */
  function set({ theme: nextValue, lang: nextLang } = {}) {
    let changed = false;
    if (nextValue && nextValue !== state.theme) {
      state.theme = nextValue;
      applyTheme();
      changed = true;
    }
    if (nextLang && nextLang !== state.lang) {
      state.lang = nextLang;
      document.documentElement.setAttribute('lang', nextLang);
      changed = true;
    }
    if (changed) build();
  }

  // A tap or a click outside an open menu, or Escape, closes it: over the
  // map the browser's own <details> would stay open behind the reader. A link
  // tapped in the menu closes it too (the site's HeaderMenuClose).
  const closeOutside = (event) => {
    for (const open of header.querySelectorAll?.('details[open]') ?? []) {
      if (!open.contains(event.target) || event.target?.closest?.('a')) open.removeAttribute('open');
    }
  };
  document.addEventListener?.('click', closeOutside, true);
  // Capturing: the planner's canvas keeps a press on the map to itself.
  document.addEventListener?.(
    'pointerdown',
    (event) => {
      for (const open of header.querySelectorAll?.('details[open]') ?? []) {
        if (!open.contains(event.target)) open.removeAttribute('open');
      }
    },
    true,
  );
  document.addEventListener?.('keydown', (event) => {
    if (event.key !== 'Escape') return;
    for (const open of header.querySelectorAll?.('details[open]') ?? []) open.removeAttribute('open');
  });

  applyTheme();
  document.documentElement.setAttribute('lang', state.lang);
  build();
  return { element: header, set, state };
}
