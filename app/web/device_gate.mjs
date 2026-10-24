// SPDX-License-Identifier: AGPL-3.0-only
// Decides, before the Flutter engine is fetched, whether this visit gets the
// web planner or the app download page, and puts the website's header
// (site_header.mjs) above either. Phones and tablets (iOS, iPadOS, Android)
// get the page, so they never download the engine; everything else gets the
// planner at once, in an element below the header (#velorki-app, which
// flutter_bootstrap.js hands the engine). "Continue in the browser" loads the
// planner for this visit only: nothing is remembered. Run by index.html;
// tested by app/web_test/ with `node --test app/web_test/` (outside
// app/web/, which flutter build copies into the site).

import {
  HEADER_CSS,
  appIcon,
  el,
  pickLanguage,
  renderHeader,
  storeLocale,
  storeTheme,
  storedLocale,
  storedTheme,
  svg,
} from './site_header.mjs';

export { SITE_URL, pickLanguage, siteUrl } from './site_header.mjs';

export const APP_STORE_URL = 'https://apps.apple.com/app/id6816790504';
export const PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=com.orkitec.velorki';

/**
 * The download page's wording. Everything but `continue` is the website's
 * own text (web/messages/<lang>.json, held to it by the test): `heading` is
 * `home.hero.stores`, `description` is `site.description`, the badges
 * `home.hero.storeIos`/`storeAndroid`. The header's is in site_header.mjs.
 */
export const STRINGS = {
  en: {
    heading: 'Get the app',
    description:
      'Velorki plans bike routes, builds loops and records your rides — on the phone, offline, free and with no account. Your routes and rides stay with you, on your phone or in your own cloud, ready to export any time, and the code is open for anyone to check.',
    storeIos: 'Download on the App Store',
    storeAndroid: 'Get it on Google Play',
    continue: 'Continue in the browser',
  },
  de: {
    heading: 'App holen',
    description:
      'Velorki plant Radrouten, baut Runden und zeichnet deine Fahrten auf, auf dem Handy, offline, kostenlos und ohne Konto. Deine Routen und Fahrten bleiben bei dir, auf deinem Handy oder in deiner eigenen Cloud, jederzeit exportierbar, und der Code ist offen, damit jeder das nachprüfen kann.',
    storeIos: 'Laden im App Store',
    storeAndroid: 'Jetzt bei Google Play',
    continue: 'Im Browser weiter',
  },
  es: {
    heading: 'Consigue la app',
    description:
      'Velorki planifica rutas en bici, crea rutas circulares y graba tus salidas: en el teléfono, sin conexión, gratis y sin cuenta. Tus rutas y salidas se quedan contigo, en tu teléfono o en tu propia nube, listas para exportar cuando quieras, y el código es abierto para que cualquiera lo compruebe.',
    storeIos: 'Descárgalo en el App Store',
    storeAndroid: 'Disponible en Google Play',
    continue: 'Continuar en el navegador',
  },
  fr: {
    heading: 'Obtenir l’application',
    description:
      'Velorki planifie vos itinéraires vélo, crée des boucles et enregistre vos sorties — sur le téléphone, hors ligne, gratuitement et sans compte. Vos itinéraires et vos sorties restent chez vous, sur votre téléphone ou dans votre propre cloud, exportables à tout moment, et le code est ouvert pour que chacun puisse le vérifier.',
    storeIos: 'Télécharger dans l’App Store',
    storeAndroid: 'Disponible sur Google Play',
    continue: 'Continuer dans le navigateur',
  },
  it: {
    heading: "Scarica l'app",
    description:
      'Velorki pianifica percorsi in bici, crea anelli e registra i tuoi giri: sul telefono, offline, gratis e senza account. I tuoi percorsi e giri restano con te, sul telefono o nel tuo cloud, esportabili quando vuoi, e il codice è aperto perché chiunque possa verificarlo.',
    storeIos: 'Scarica su App Store',
    storeAndroid: 'Disponibile su Google Play',
    continue: 'Continua nel browser',
  },
  nl: {
    heading: 'Download de app',
    description:
      'Velorki plant fietsroutes, maakt rondjes en neemt je ritten op — op de telefoon, offline, gratis en zonder account. Je routes en ritten blijven bij jou, op je telefoon of in je eigen cloud, altijd te exporteren, en de code is open zodat iedereen dat kan controleren.',
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

/**
 * purchases_flutter's web plugin appends RevenueCat's web SDK (some 900 KB)
 * to <head> as the engine starts, whether anything is sold or not. The web
 * planner sells nothing (no store, `NoopSubscriptionService`), so `head`
 * leaves that one script out and appends everything else as before.
 */
export const STORE_SDK = /\/purchases_flutter\//;

export function leaveOutStoreSdk(head) {
  const append = head.append;
  head.append = function (...nodes) {
    return append.apply(this, nodes.filter((node) => !STORE_SDK.test(node?.src ?? '')));
  };
}

/**
 * google_sign_in's web plugin appends Google Identity Services' script to
 * <head> as the engine starts. The planner asks nothing of Google until the
 * rider picks Google in Settings → Sync with, so `head` holds that script
 * back until the app calls `velorkiLoadGoogleSdk()` on `target` (the
 * window); then it goes in as the plugin made it.
 */
export const GOOGLE_SDK = /^https:\/\/accounts\.google\.com\/gsi\/client/;

export function holdBackGoogleSdk(head, target) {
  const held = [];
  let released = false;
  const appendChild = head.appendChild;
  head.appendChild = function (node) {
    if (!released && GOOGLE_SDK.test(node?.src ?? '')) {
      held.push(node);
      return node;
    }
    return appendChild.call(this, node);
  };
  target.velorkiLoadGoogleSdk = () => {
    released = true;
    for (const node of held.splice(0)) appendChild.call(head, node);
  };
}

/** The element the planner runs in, below the header; the engine is
    appended once, and only after it is there. */
export function loadApp(document, window = globalThis) {
  if (document.getElementById('flutter-bootstrap')) return;
  if (!document.getElementById('velorki-app')) {
    document.body.setAttribute('class', 'vg-app');
    document.body.appendChild(document.createElement('div')).setAttribute('id', 'velorki-app');
  }
  leaveOutStoreSdk(document.head);
  holdBackGoogleSdk(document.head, window);
  const script = document.createElement('script');
  script.id = 'flutter-bootstrap';
  script.src = 'flutter_bootstrap.js';
  script.async = true;
  document.body.appendChild(script);
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

// The page's own (web/src/app/globals.css: the hero, .btn-secondary); the
// planner's body is a column, the header over the app's element.
const PAGE_CSS = `
.vg-app{display:flex;flex-direction:column;height:100vh;height:100dvh;overflow:hidden}
.vg-app>.vh{position:relative;flex:none}
#velorki-app{position:relative;flex:1 1 auto;min-height:0}
.vg{color:var(--fg);font:500 1rem/1.55 Manrope,ui-sans-serif,system-ui,-apple-system,sans-serif;-webkit-font-smoothing:antialiased;-webkit-text-size-adjust:100%}
.vg a{color:inherit;text-decoration:none}
.vg-main{max-width:30rem;margin-inline:auto;padding:3rem max(1.25rem,env(safe-area-inset-left,0px)) calc(3rem + env(safe-area-inset-bottom,0px))}
.vg h1{font-family:'Barlow Condensed',ui-sans-serif,sans-serif;font-weight:700;letter-spacing:-.01em;font-size:2.75rem;line-height:1.02;margin:1.5rem 0 .75rem;text-wrap:balance}
.vg p{margin:0;color:var(--muted)}
.vg ul{list-style:none;margin:2rem 0 0;padding:0;display:flex;flex-wrap:wrap;gap:.75rem}
.vg-btn{display:inline-flex;align-items:center;gap:.5rem;min-height:3.25rem;padding:0 1.5rem;border-radius:999px;font-weight:700;font-size:.9375rem;border:1px solid var(--line);background:var(--panel);color:var(--fg)}
.vg-btn:hover{border-color:var(--accent)}
.vg-continue{margin-top:2rem;padding:.5rem 0;border:0;background:none;font:inherit;font-size:.875rem;font-weight:700;color:var(--muted);text-decoration:underline;text-underline-offset:3px;cursor:pointer}
.vg-continue:hover{color:var(--fg)}
`;

/**
 * Builds the download page's content into `document` in `lang` and returns
 * it with a way to take it away again. `onContinue` runs after it is gone.
 */
export function renderDownloadPage(document, lang, onContinue) {
  const t = STRINGS[lang] ?? STRINGS.en;
  const store = (href, glyph, label) =>
    el(document, 'li', {}, [el(document, 'a', { href, rel: 'noreferrer', class: 'vg-btn' }, [glyph, label])]);
  const proceed = el(document, 'button', { type: 'button', class: 'vg-continue' }, [t.continue]);
  const page = el(document, 'main', { class: 'vg vg-main', id: 'velorki-gate' }, [
    appIcon(document, 72),
    el(document, 'h1', {}, [t.heading]),
    el(document, 'p', {}, [t.description]),
    el(document, 'ul', {}, [
      store(APP_STORE_URL, icon(document, APPLE.map((d) => [d, 1])), t.storeIos),
      store(PLAY_STORE_URL, icon(document, GOOGLE_PLAY), t.storeAndroid),
    ]),
    proceed,
  ]);
  const remove = () => page.remove();
  proceed.addEventListener('click', () => {
    remove();
    onContinue();
  });
  document.body.appendChild(page);
  return remove;
}

/** The app's language for the header: the one it keeps, else the browser's. */
function appLanguage(window) {
  const { navigator } = window;
  return (
    storedLocale(window.localStorage) ??
    pickLanguage(navigator.languages?.length ? navigator.languages : [navigator.language])
  );
}

/**
 * Index.html's entry point: the header, and below it the download page on a
 * phone or tablet, else the planner. The header's theme and language are
 * the app's (site_header.mjs); a pick there is kept where the app keeps it
 * and announced as `velorki-header`, and `velorki-app-settings` from the app
 * brings a change made in its own settings back to the header.
 */
export function boot(window) {
  const { document, navigator } = window;
  const mobile = isMobileDevice(navigator);
  const storage = window.localStorage;
  let gate = null;
  let removeGate = null;
  const announce = (detail) => {
    const Event = window.CustomEvent ?? globalThis.CustomEvent;
    if (Event) window.dispatchEvent?.(new Event('velorki-header', { detail }));
  };
  const header = renderHeader(window, {
    lang: appLanguage(window),
    theme: storedTheme(storage),
    onTheme: (theme) => {
      storeTheme(storage, theme);
      announce({ theme });
    },
    onLanguage: (lang) => {
      storeLocale(storage, lang);
      announce({ locale: lang });
      if (gate) showGate(lang);
    },
  });
  window.addEventListener?.('velorki-app-settings', (event) => {
    const { theme, locale } = event.detail ?? {};
    header.set({ theme, lang: locale ?? appLanguage(window) });
  });

  document.head.appendChild(el(document, 'style', { id: 'velorki-style' }, [HEADER_CSS + PAGE_CSS]));
  document.body.appendChild(header.element);
  if (!mobile) {
    loadApp(document, window);
    return;
  }
  function showGate(lang) {
    removeGate?.();
    gate = lang;
    removeGate = renderDownloadPage(document, lang, () => {
      gate = null;
      header.set({});
      loadApp(document, window);
    });
  }
  showGate(header.state.lang);
}
