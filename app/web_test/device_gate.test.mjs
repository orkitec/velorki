// SPDX-License-Identifier: AGPL-3.0-only
// node --test app/web_test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { STRINGS, boot, isMobileDevice, pickLanguage, siteUrl } from '../web/device_gate.mjs';

const repo = (path) => fileURLToPath(new URL(`../../${path}`, import.meta.url));
const LANGS = ['en', 'de', 'es', 'fr', 'it', 'nl'];

const UA = {
  iPhone:
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
  iPod: 'Mozilla/5.0 (iPod touch; CPU iPhone OS 15_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.7 Mobile/15E148 Safari/604.1',
  oldIpad:
    'Mozilla/5.0 (iPad; CPU OS 12_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1 Mobile/15E148 Safari/604.1',
  macSafari:
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15',
  macChrome:
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  androidPhone:
    'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36',
  androidTablet:
    'Mozilla/5.0 (Linux; Android 14; SM-X710) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  windowsChrome:
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  windowsEdge:
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0',
  linuxFirefox: 'Mozilla/5.0 (X11; Linux x86_64; rv:143.0) Gecko/20100101 Firefox/143.0',
  chromeOS:
    'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
};

test('phones and tablets are mobile', () => {
  assert.equal(isMobileDevice({ userAgent: UA.iPhone, maxTouchPoints: 5, platform: 'iPhone' }), true);
  assert.equal(isMobileDevice({ userAgent: UA.iPod, maxTouchPoints: 5, platform: 'iPod' }), true);
  assert.equal(isMobileDevice({ userAgent: UA.oldIpad, maxTouchPoints: 5, platform: 'iPad' }), true);
  assert.equal(isMobileDevice({ userAgent: UA.androidPhone, maxTouchPoints: 5, platform: 'Linux armv8l' }), true);
  assert.equal(isMobileDevice({ userAgent: UA.androidTablet, maxTouchPoints: 10, platform: 'Linux armv8l' }), true);
});

test('iPadOS Safari says Macintosh but has touch points', () => {
  assert.equal(isMobileDevice({ userAgent: UA.macSafari, maxTouchPoints: 5, platform: 'MacIntel' }), true);
});

test('desktops are not mobile, touch screen or not', () => {
  assert.equal(isMobileDevice({ userAgent: UA.macSafari, maxTouchPoints: 0, platform: 'MacIntel' }), false);
  assert.equal(isMobileDevice({ userAgent: UA.macChrome, maxTouchPoints: 0, platform: 'MacIntel' }), false);
  assert.equal(isMobileDevice({ userAgent: UA.windowsChrome, maxTouchPoints: 0, platform: 'Win32' }), false);
  assert.equal(isMobileDevice({ userAgent: UA.windowsEdge, maxTouchPoints: 0, platform: 'Win32' }), false);
  assert.equal(isMobileDevice({ userAgent: UA.windowsEdge, maxTouchPoints: 10, platform: 'Win32' }), false);
  assert.equal(isMobileDevice({ userAgent: UA.linuxFirefox, maxTouchPoints: 0, platform: 'Linux x86_64' }), false);
  assert.equal(isMobileDevice({ userAgent: UA.chromeOS, maxTouchPoints: 10, platform: 'Linux x86_64' }), false);
  assert.equal(isMobileDevice({}), false);
});

test('pickLanguage takes the first supported language, else English', () => {
  assert.equal(pickLanguage(['de-DE']), 'de');
  assert.equal(pickLanguage(['fr-CA', 'en']), 'fr');
  assert.equal(pickLanguage(['pt-BR']), 'en');
  assert.equal(pickLanguage([]), 'en');
  assert.equal(pickLanguage(undefined), 'en');
  assert.equal(pickLanguage(['pt-BR', 'it', 'de']), 'it');
  assert.equal(pickLanguage(['NL']), 'nl');
});

test('every string exists in every language', () => {
  assert.deepEqual(Object.keys(STRINGS).sort(), [...LANGS].sort());
  for (const key of Object.keys(STRINGS.en)) {
    for (const lang of LANGS) {
      assert.equal(typeof STRINGS[lang][key], 'string', `${lang}.${key}`);
      assert.notEqual(STRINGS[lang][key].trim(), '', `${lang}.${key}`);
    }
  }
  for (const lang of LANGS) assert.deepEqual(Object.keys(STRINGS[lang]).sort(), Object.keys(STRINGS.en).sort());
});

test("the reused wording is the website's", () => {
  for (const lang of LANGS) {
    const m = JSON.parse(readFileSync(repo(`web/messages/${lang}.json`), 'utf8'));
    const t = STRINGS[lang];
    assert.equal(t.heading, m.home.hero.stores, lang);
    assert.equal(t.description, m.site.description, lang);
    assert.equal(t.storeIos, m.home.hero.storeIos, lang);
    assert.equal(t.storeAndroid, m.home.hero.storeAndroid, lang);
  }
});

test("the store glyphs are the website's", () => {
  const icons = readFileSync(repo('web/src/components/Icons.tsx'), 'utf8');
  const gate = readFileSync(fileURLToPath(new URL('../web/device_gate.mjs', import.meta.url)), 'utf8');
  const block = (name) => icons.slice(icons.indexOf(`function ${name}`), icons.indexOf('\n}\n', icons.indexOf(`function ${name}`)));
  for (const name of ['AppleIcon', 'GooglePlayIcon']) {
    const paths = [...block(name).matchAll(/d="([^"]+)"/g)].map((m) => m[1]);
    assert.ok(paths.length > 0, name);
    for (const d of paths) assert.ok(gate.includes(d), `${name}: ${d}`);
  }
});

test("site links follow the website's locale scheme", () => {
  assert.equal(siteUrl('en'), 'https://velorki.com/');
  assert.equal(siteUrl('en', '/docs'), 'https://velorki.com/docs');
  assert.equal(siteUrl('de'), 'https://velorki.com/de');
  assert.equal(siteUrl('de', '/plus'), 'https://velorki.com/de/plus');
  assert.equal(siteUrl('fr', '/#features'), 'https://velorki.com/fr/#features');
});

// Just enough DOM for device_gate.mjs.
class FakeNode {
  constructor(tag, doc) {
    this.tagName = tag;
    this.ownerDocument = doc;
    this.children = [];
    this.attributes = {};
    this.listeners = {};
    this.parent = null;
    this.text = '';
  }
  setAttribute(k, v) {
    this.attributes[k] = String(v);
  }
  getAttribute(k) {
    return this.attributes[k] ?? null;
  }
  removeAttribute(k) {
    delete this.attributes[k];
  }
  get firstChild() {
    return this.children[0] ?? null;
  }
  removeChild(child) {
    child.remove();
    return child;
  }
  contains(node) {
    return [...this.walk()].includes(node);
  }
  querySelectorAll() {
    return [];
  }
  appendChild(child) {
    child.parent = this;
    this.children.push(child);
    return child;
  }
  append(...nodes) {
    for (const n of nodes) this.appendChild(n);
  }
  remove() {
    if (!this.parent) return;
    this.parent.children = this.parent.children.filter((c) => c !== this);
    this.parent = null;
  }
  addEventListener(type, fn) {
    (this.listeners[type] ??= []).push(fn);
  }
  click() {
    for (const fn of this.listeners.click ?? []) fn({ type: 'click' });
  }
  get textContent() {
    return this.text + this.children.map((c) => c.textContent).join('');
  }
  *walk() {
    yield this;
    for (const c of this.children) yield* c.walk();
  }
}

function fakeWindow(navigator, stored = {}) {
  const doc = {
    createElement: (tag) => new FakeNode(tag, doc),
    createElementNS: (_ns, tag) => new FakeNode(tag, doc),
    createTextNode: (text) => Object.assign(new FakeNode('#text', doc), { text }),
    getElementById: (id) => [...doc.documentElement.walk()].find((n) => n.id === id || n.attributes.id === id) ?? null,
  };
  doc.documentElement = new FakeNode('html', doc);
  doc.head = doc.documentElement.appendChild(new FakeNode('head', doc));
  doc.body = doc.documentElement.appendChild(new FakeNode('body', doc));
  const items = new Map(Object.entries(stored));
  const localStorage = {
    getItem: (k) => items.get(k) ?? null,
    setItem: (k, v) => items.set(k, String(v)),
    removeItem: (k) => items.delete(k),
  };
  const listeners = {};
  return {
    document: doc,
    navigator,
    localStorage,
    items,
    addEventListener: (type, fn) => (listeners[type] ??= []).push(fn),
    dispatchEvent: (event) => {
      for (const fn of listeners[event.type] ?? []) fn(event);
      return true;
    },
  };
}

const scripts = (doc) => [...doc.documentElement.walk()].filter((n) => n.tagName === 'script');
const byId = (doc, id) => [...doc.documentElement.walk()].find((n) => n.attributes.id === id);
const find = (doc, pred) => [...doc.documentElement.walk()].find(pred);

test('boot loads the app on a desktop', () => {
  const w = fakeWindow({ userAgent: UA.windowsChrome, maxTouchPoints: 0, platform: 'Win32', languages: ['de-DE'] });
  boot(w);
  const s = scripts(w.document);
  assert.equal(s.length, 1);
  assert.equal(s[0].src, 'flutter_bootstrap.js');
  assert.equal(s[0].async, true);
  assert.equal(find(w.document, (n) => n.attributes.id === 'velorki-gate'), undefined);
  // The site's header, and the app's element below it, before the engine.
  const body = w.document.body.children.map((n) => n.attributes.id);
  assert.deepEqual(body.slice(0, 2), ['velorki-header', 'velorki-app']);
  assert.equal(w.document.body.attributes.class, 'vg-app');
});

test('boot shows the download page on a phone, and continuing loads the app once', () => {
  const w = fakeWindow({ userAgent: UA.iPhone, maxTouchPoints: 5, platform: 'iPhone', languages: ['de-DE', 'en'] });
  boot(w);
  assert.equal(scripts(w.document).length, 0);
  const page = find(w.document, (n) => n.attributes.id === 'velorki-gate');
  assert.ok(page);
  assert.equal(w.document.documentElement.attributes.lang, 'de');
  const text = page.textContent;
  for (const key of ['heading', 'description', 'storeIos', 'storeAndroid', 'continue']) {
    assert.ok(text.includes(STRINGS.de[key]), key);
  }
  const hrefs = [...page.walk()].map((n) => n.attributes.href).filter(Boolean);
  assert.ok(hrefs.includes('https://apps.apple.com/app/id6816790504'));
  assert.ok(hrefs.includes('https://play.google.com/store/apps/details?id=com.orkitec.velorki'));
  const header = byId(w.document, 'velorki-header');
  assert.ok([...header.walk()].some((n) => n.attributes.href === 'https://velorki.com/de/docs'));

  find(w.document, (n) => n.attributes.class === 'vg-continue').click();
  assert.equal(find(w.document, (n) => n.attributes.id === 'velorki-gate'), undefined);
  // The header stays, now over the planner.
  assert.ok(byId(w.document, 'velorki-header'));
  assert.ok(byId(w.document, 'velorki-app'));
  assert.equal(scripts(w.document).length, 1);
  assert.equal(scripts(w.document)[0].src, 'flutter_bootstrap.js');
});

test("the header's language is the app's when it keeps one", () => {
  const w = fakeWindow(
    { userAgent: UA.iPhone, maxTouchPoints: 5, languages: ['de-DE'] },
    { 'flutter.language.locale': JSON.stringify('fr') },
  );
  boot(w);
  assert.equal(w.document.documentElement.attributes.lang, 'fr');
  assert.ok(byId(w.document, 'velorki-gate').textContent.includes(STRINGS.fr.continue));
});

test('boot falls back to navigator.language, then English', () => {
  const w = fakeWindow({ userAgent: UA.androidTablet, maxTouchPoints: 10, language: 'nl-BE' });
  boot(w);
  assert.equal(w.document.documentElement.attributes.lang, 'nl');
  const w2 = fakeWindow({ userAgent: UA.androidPhone, maxTouchPoints: 5, languages: ['ja-JP'] });
  boot(w2);
  assert.equal(w2.document.documentElement.attributes.lang, 'en');
});

test("loading the app leaves RevenueCat's web SDK out of <head>, and only that", () => {
  const w = fakeWindow({ userAgent: UA.windowsChrome, maxTouchPoints: 0, platform: 'Win32', languages: ['en'] });
  boot(w);
  const head = w.document.head;
  const sdk = Object.assign(w.document.createElement('script'), {
    src: 'assets/packages/purchases_flutter/assets/web/purchases_js_hybrid_mappings.js',
  });
  const css = Object.assign(w.document.createElement('link'), { href: 'maplibre-gl/maplibre-gl.css' });
  const before = head.children.length;
  head.append(sdk, css);
  assert.equal(head.children.length, before + 1);
  assert.equal(head.children.at(-1), css);
});

test("Google's sign-in script waits in <head> until the app asks for it", () => {
  const w = fakeWindow({ userAgent: UA.windowsChrome, maxTouchPoints: 0, platform: 'Win32', languages: ['en'] });
  boot(w);
  const head = w.document.head;
  const gis = Object.assign(w.document.createElement('script'), { src: 'https://accounts.google.com/gsi/client' });
  const other = Object.assign(w.document.createElement('script'), { src: 'assets/other.js' });
  const before = head.children.length;
  head.appendChild(gis);
  head.appendChild(other);
  assert.equal(head.children.length, before + 1);
  assert.equal(head.children.at(-1), other);
  w.velorkiLoadGoogleSdk();
  assert.equal(head.children.at(-1), gis);
  // Once let in, it is not held again.
  const again = Object.assign(w.document.createElement('script'), { src: 'https://accounts.google.com/gsi/client' });
  head.appendChild(again);
  assert.equal(head.children.at(-1), again);
});
