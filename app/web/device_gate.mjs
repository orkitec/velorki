// SPDX-License-Identifier: AGPL-3.0-only
// Decides, before the Flutter engine is fetched, whether this visit gets the
// web planner or the app download page. Phones and tablets (iOS, iPadOS,
// Android) get the page, so they never download the engine; everything else
// gets the app at once. "Continue in the browser" loads the app for this
// visit only: nothing is remembered. Run by index.html; tested by
// app/web_test/ with `node --test app/web_test/` (outside app/web/,
// which flutter build copies into the site).

export const APP_STORE_URL = 'https://apps.apple.com/app/id6816790504';
export const PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=com.orkitec.velorki';
export const SITE_URL = 'https://velorki.com';

/**
 * The page's wording. Everything but `continue` is the website's own text
 * (web/messages/<lang>.json, held to it by the test): `home`, `primary` and
 * the three links from `nav`, `heading` is `home.hero.stores`, `description`
 * is `site.description`, the badges `home.hero.storeIos`/`storeAndroid`.
 */
export const STRINGS = {
  en: {
    home: 'Velorki home',
    primary: 'Main',
    features: 'Features',
    docs: 'Docs',
    plus: 'Plus',
    heading: 'Get the app',
    description:
      'Velorki plans bike routes, builds loops and records your rides — on the phone, offline, on OpenStreetMap data. Free and open source.',
    storeIos: 'Download on the App Store',
    storeAndroid: 'Get it on Google Play',
    continue: 'Continue in the browser',
  },
  de: {
    home: 'Velorki Startseite',
    primary: 'Haupt',
    features: 'Funktionen',
    docs: 'Doku',
    plus: 'Plus',
    heading: 'App holen',
    description:
      'Velorki plant Radrouten, baut Runden und zeichnet deine Fahrten auf, auf dem Handy, offline, mit OpenStreetMap-Daten. Kostenlos und quelloffen.',
    storeIos: 'Laden im App Store',
    storeAndroid: 'Jetzt bei Google Play',
    continue: 'Im Browser weiter',
  },
  es: {
    home: 'Inicio de Velorki',
    primary: 'Principal',
    features: 'Funciones',
    docs: 'Ayuda',
    plus: 'Plus',
    heading: 'Consigue la app',
    description:
      'Velorki planifica rutas en bici, crea rutas circulares y graba tus salidas: en el teléfono, sin conexión, con datos de OpenStreetMap. Gratis y de código abierto.',
    storeIos: 'Descárgalo en el App Store',
    storeAndroid: 'Disponible en Google Play',
    continue: 'Continuar en el navegador',
  },
  fr: {
    home: 'Accueil Velorki',
    primary: 'Principal',
    features: 'Fonctions',
    docs: 'Guide',
    plus: 'Plus',
    heading: 'Obtenir l’application',
    description:
      'Velorki planifie vos itinéraires vélo, crée des boucles et enregistre vos sorties — sur le téléphone, hors ligne, avec les données OpenStreetMap. Gratuit et open source.',
    storeIos: 'Télécharger dans l’App Store',
    storeAndroid: 'Disponible sur Google Play',
    continue: 'Continuer dans le navigateur',
  },
  it: {
    home: 'Pagina iniziale di Velorki',
    primary: 'Principale',
    features: 'Funzionalità',
    docs: 'Guida',
    plus: 'Plus',
    heading: "Scarica l'app",
    description:
      'Velorki pianifica percorsi in bici, crea anelli e registra i tuoi giri: sul telefono, offline, con i dati di OpenStreetMap. Gratis e open source.',
    storeIos: 'Scarica su App Store',
    storeAndroid: 'Disponibile su Google Play',
    continue: 'Continua nel browser',
  },
  nl: {
    home: 'Velorki-startpagina',
    primary: 'Hoofdmenu',
    features: 'Functies',
    docs: 'Handleiding',
    plus: 'Plus',
    heading: 'Download de app',
    description:
      'Velorki plant fietsroutes, maakt rondjes en neemt je ritten op — op de telefoon, offline, met OpenStreetMap-gegevens. Gratis en open source.',
    storeIos: 'Download in de App Store',
    storeAndroid: 'Ontdek het op Google Play',
    continue: 'Verder in de browser',
  },
};

/**
 * iPhone, iPod, iPad and every Android device, tablets included. iPadOS 13+
 * Safari says "Macintosh", so a Mac that reports more than one touch point
 * is an iPad (no Mac has a touch screen). A Windows or ChromeOS touch screen
 * stays a desktop.
 */
export function isMobileDevice({ userAgent = '', maxTouchPoints = 0, platform = '' } = {}) {
  if (/iPhone|iPod|iPad|Android/.test(userAgent)) return true;
  const mac = /Macintosh/.test(userAgent) || platform === 'MacIntel';
  return mac && maxTouchPoints > 1;
}

/** The first of the reader's languages the page is written in, else English. */
export function pickLanguage(languages) {
  for (const tag of languages ?? []) {
    const lang = String(tag).toLowerCase().split(/[-_]/)[0];
    if (Object.prototype.hasOwnProperty.call(STRINGS, lang)) return lang;
  }
  return 'en';
}

/** The website's localized URL for `path`; English is unprefixed, as on the site. */
export function siteUrl(lang, path = '/') {
  if (lang === 'en') return `${SITE_URL}${path}`;
  return path === '/' ? `${SITE_URL}/${lang}` : `${SITE_URL}/${lang}${path}`;
}

/** Appends the Flutter loader once; the page and the desktop path share it. */
export function loadApp(document) {
  if (document.getElementById('flutter-bootstrap')) return;
  const script = document.createElement('script');
  script.id = 'flutter-bootstrap';
  script.src = 'flutter_bootstrap.js';
  script.async = true;
  document.body.appendChild(script);
}

const SVG_NS = 'http://www.w3.org/2000/svg';

function el(document, tag, attrs = {}, children = []) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  for (const child of children) {
    node.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
  }
  return node;
}

function svg(document, tag, attrs = {}, children = []) {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  for (const child of children) node.appendChild(child);
  return node;
}

// web/public/icon.svg, coloured by --tile and --glyph.
function appIcon(document, size) {
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

// web/src/components/Icons.tsx: AppleIcon, GooglePlayIcon.
const APPLE = [
  'M16.37 12.63c.02-2.2 1.8-3.26 1.88-3.31-1.03-1.5-2.62-1.71-3.19-1.73-1.36-.14-2.65.8-3.34.8-.69 0-1.75-.78-2.88-.76-1.48.02-2.85.86-3.61 2.19-1.54 2.67-.39 6.62 1.11 8.79.73 1.06 1.6 2.25 2.75 2.2 1.1-.04 1.52-.71 2.86-.71 1.33 0 1.71.71 2.88.69 1.19-.02 1.94-1.08 2.67-2.14.84-1.23 1.19-2.42 1.2-2.48-.02-.01-2.31-.89-2.33-3.54ZM14.2 6.2c.6-.74 1.01-1.76.9-2.78-.87.04-1.93.58-2.56 1.31-.56.65-1.05 1.69-.92 2.68.97.08 1.96-.49 2.58-1.21Z',
];
const GOOGLE_PLAY = [
  ['M3.6 2.3c-.23.24-.36.6-.36 1.07v17.26c0 .47.13.83.36 1.07l.09.08 9.67-9.67v-.23L3.69 2.22l-.09.08Z', 1],
  ['m16.6 15.36-3.24-3.25v-.23l3.24-3.24.07.04 3.84 2.18c1.1.62 1.1 1.64 0 2.27l-3.84 2.18-.07.05Z', 1],
  ['m16.67 15.31-3.31-3.31-9.76 9.76c.36.39.96.43 1.64.05l11.43-6.5Z', 0.85],
  ['M16.67 8.69 5.24 2.19c-.68-.39-1.28-.34-1.64.05l9.76 9.76 3.31-3.31Z', 0.7],
];

function icon(document, paths) {
  return svg(
    document,
    'svg',
    { viewBox: '0 0 24 24', width: 20, height: 20, 'aria-hidden': 'true', focusable: 'false' },
    paths.map(([d, opacity]) => svg(document, 'path', { d, fill: 'currentColor', opacity })),
  );
}

// The website's tokens (web/src/app/globals.css), header and .btn-secondary.
const CSS = `
@font-face{font-family:Manrope;src:url(fonts/Manrope-latin.woff2) format('woff2');font-weight:400 700;font-display:swap}
@font-face{font-family:'Barlow Condensed';src:url(fonts/BarlowCondensed-Bold-latin.woff2) format('woff2');font-weight:700;font-display:swap}
:root{color-scheme:light dark;--canvas:#f5f6f3;--panel:#fff;--fg:#14171a;--muted:#5b636c;--line:#d7dbd5;--line-soft:#e4e7e2;--accent:#3f7a00;--accent-soft:rgb(63 122 0/.12);--tile:#3f7a00;--glyph:#fff}
@media (prefers-color-scheme:dark){:root{--canvas:#0e1115;--panel:#1b1f26;--fg:#f1f3f5;--muted:#aab2bc;--line:#2c333c;--line-soft:#232930;--accent:#c8f542;--accent-soft:rgb(200 245 66/.14);--tile:#c8f542;--glyph:#0e1115}}
html,body{margin:0;background:var(--canvas)}
.vg{min-height:100vh;color:var(--fg);font:500 1rem/1.55 Manrope,ui-sans-serif,system-ui,-apple-system,sans-serif;-webkit-font-smoothing:antialiased;-webkit-text-size-adjust:100%}
.vg a{color:inherit;text-decoration:none}
.vg-tile{fill:var(--tile)}.vg-glyph{fill:var(--glyph)}.vg-route{fill:none;stroke:var(--glyph)}
.vg-header{border-bottom:1px solid var(--line-soft);padding-top:env(safe-area-inset-top,0px)}
.vg-shell{max-width:76rem;margin-inline:auto;padding-inline:max(1.25rem,env(safe-area-inset-left,0px))}
.vg-bar{display:flex;flex-wrap:wrap;align-items:center;gap:.25rem .5rem;min-height:4rem}
.vg-brand{display:flex;align-items:center;gap:.5rem;margin-right:auto}
.vg-word,.vg h1{font-family:'Barlow Condensed',ui-sans-serif,sans-serif;font-weight:700;letter-spacing:-.01em}
.vg-word{font-size:1.25rem;line-height:1}
.vg-nav{display:flex;gap:.125rem;margin-inline:-.5rem}
.vg-nav a{border-radius:999px;padding:.5rem;font-size:.875rem;font-weight:700;color:var(--muted)}
.vg-nav a:hover{background:var(--accent-soft);color:var(--fg)}
.vg-main{max-width:30rem;padding-block:3rem calc(3rem + env(safe-area-inset-bottom,0px))}
.vg h1{font-size:2.75rem;line-height:1.02;margin:1.5rem 0 .75rem;text-wrap:balance}
.vg p{margin:0;color:var(--muted)}
.vg ul{list-style:none;margin:2rem 0 0;padding:0;display:flex;flex-wrap:wrap;gap:.75rem}
.vg-btn{display:inline-flex;align-items:center;gap:.5rem;min-height:3.25rem;padding:0 1.5rem;border-radius:999px;font-weight:700;font-size:.9375rem;border:1px solid var(--line);background:var(--panel);color:var(--fg)}
.vg-btn:hover{border-color:var(--accent)}
.vg-continue{margin-top:2rem;padding:.5rem 0;border:0;background:none;font:inherit;font-size:.875rem;font-weight:700;color:var(--muted);text-decoration:underline;text-underline-offset:3px;cursor:pointer}
.vg-continue:hover{color:var(--fg)}
`;

/**
 * Builds the download page into `document` and returns a function that
 * takes it away again. `onContinue` runs after the page is gone.
 */
export function renderDownloadPage(document, lang, onContinue) {
  const t = STRINGS[lang] ?? STRINGS.en;
  const style = el(document, 'style', {}, [CSS]);
  const nav = [
    ['features', '/#features'],
    ['docs', '/docs'],
    ['plus', '/plus'],
  ].map(([key, path]) => el(document, 'a', { href: siteUrl(lang, path) }, [t[key]]));
  const store = (href, glyph, label) =>
    el(document, 'li', {}, [el(document, 'a', { href, rel: 'noreferrer', class: 'vg-btn' }, [glyph, label])]);
  const proceed = el(document, 'button', { type: 'button', class: 'vg-continue' }, [t.continue]);
  const page = el(document, 'div', { class: 'vg', id: 'velorki-gate' }, [
    el(document, 'header', { class: 'vg-header' }, [
      el(document, 'div', { class: 'vg-shell vg-bar' }, [
        el(document, 'a', { href: siteUrl(lang), 'aria-label': t.home, class: 'vg-brand' }, [
          appIcon(document, 32),
          el(document, 'span', { class: 'vg-word' }, ['Velorki']),
        ]),
        el(document, 'nav', { 'aria-label': t.primary, class: 'vg-nav' }, nav),
      ]),
    ]),
    el(document, 'main', { class: 'vg-shell vg-main' }, [
      appIcon(document, 72),
      el(document, 'h1', {}, [t.heading]),
      el(document, 'p', {}, [t.description]),
      el(document, 'ul', {}, [
        store(APP_STORE_URL, icon(document, APPLE.map((d) => [d, 1])), t.storeIos),
        store(PLAY_STORE_URL, icon(document, GOOGLE_PLAY), t.storeAndroid),
      ]),
      proceed,
    ]),
  ]);
  const remove = () => {
    page.remove();
    style.remove();
  };
  proceed.addEventListener('click', () => {
    remove();
    onContinue();
  });
  document.documentElement.setAttribute('lang', lang);
  document.head.appendChild(style);
  document.body.appendChild(page);
  return remove;
}

/** Index.html's entry point: the download page on a phone or tablet, else the app. */
export function boot(window) {
  const { document, navigator } = window;
  if (!isMobileDevice(navigator)) {
    loadApp(document);
    return;
  }
  const lang = pickLanguage(navigator.languages?.length ? navigator.languages : [navigator.language]);
  renderDownloadPage(document, lang, () => loadApp(document));
}
