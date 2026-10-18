// SPDX-License-Identifier: AGPL-3.0-only
// node --test app/web_test/
// The planner's header is a copy of the website's: these hold its links,
// words, glyphs and languages to web/ and to the app, so a change on one side
// fails here until the other follows.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  GITHUB_URL,
  GLYPHS,
  HEADER_STRINGS,
  LANGS,
  LOCALE_KEY,
  LOCALE_NAMES,
  NAV,
  THEME_KEY,
  nextTheme,
  renderHeader,
  storeLocale,
  storeTheme,
  storedLocale,
  storedTheme,
} from '../web/site_header.mjs';

const repo = (path) => fileURLToPath(new URL(`../../${path}`, import.meta.url));
const read = (path) => readFileSync(repo(path), 'utf8');

test("the languages are the site's and the app's", () => {
  const site = readdirSync(repo('web/messages'))
    .filter((f) => f.endsWith('.json'))
    .map((f) => f.slice(0, -5));
  const app = readdirSync(repo('app/lib/l10n'))
    .map((f) => /^app_(\w+)\.arb$/.exec(f)?.[1])
    .filter(Boolean);
  assert.deepEqual([...LANGS].sort(), site.sort());
  assert.deepEqual([...LANGS].sort(), app.sort());
  const locales = read('web/src/site/locales.ts');
  for (const lang of LANGS) assert.ok(locales.includes(`${lang}: '${LOCALE_NAMES[lang]}'`), lang);
});

test("the words are the website's", () => {
  for (const lang of LANGS) {
    const m = JSON.parse(read(`web/messages/${lang}.json`));
    const t = HEADER_STRINGS[lang];
    assert.deepEqual(Object.keys(t).sort(), Object.keys(HEADER_STRINGS.en).sort(), lang);
    for (const key of ['home', 'primary', 'features', 'docs', 'plus', 'github', 'getApp', 'menu']) {
      assert.equal(t[key], m.nav[key], `${lang}.nav.${key}`);
    }
    assert.equal(t.theme, m.theme.label, `${lang}.theme.label`);
    for (const key of ['system', 'light', 'dark', 'cycle']) assert.equal(t[key], m.theme[key], `${lang}.theme.${key}`);
    assert.equal(t.language, m.localeSwitcher.label, `${lang}.localeSwitcher.label`);
  }
});

test("the links are the website header's, in its order", () => {
  const header = read('web/src/components/SiteHeader.tsx');
  const block = header.slice(header.indexOf('const NAV = ['), header.indexOf('] as const'));
  const site = [...block.matchAll(/\{ key: '(\w+)', href: '([^']+)' \}/g)].map(([, key, href]) => ({ key, href }));
  assert.deepEqual(NAV, site);
  // GitHub after them, then the call to action, as the site has them.
  const order = ['NAV.map', "t('github')", "t('getApp')"].map((s) => header.indexOf(s));
  for (const i of order) assert.ok(i > 0);
  assert.deepEqual([...order].sort((a, b) => a - b), order);
  assert.ok(read('web/src/site/config.ts').includes(`GITHUB_URL = '${GITHUB_URL}'`));
});

test("the glyphs are the website's", () => {
  const icons = read('web/src/components/Icons.tsx');
  const names = {
    github: 'GitHubIcon',
    globe: 'GlobeIcon',
    chevron: 'ChevronDownIcon',
    system: 'SystemThemeIcon',
    light: 'LightThemeIcon',
    dark: 'DarkThemeIcon',
    menu: 'MenuIcon',
    close: 'CloseIcon',
  };
  for (const [name, component] of Object.entries(names)) {
    const start = icons.indexOf(`function ${component}`);
    const block = icons.slice(start, icons.indexOf('\n}\n', start));
    for (const [, attrs] of GLYPHS[name]) {
      if (attrs.d) assert.ok(block.includes(attrs.d), `${name}: ${attrs.d}`);
    }
  }
});

test('the theme and the language are kept where the app keeps them', () => {
  const items = new Map();
  const storage = {
    getItem: (k) => items.get(k) ?? null,
    setItem: (k, v) => items.set(k, v),
    removeItem: (k) => items.delete(k),
  };
  assert.equal(storedTheme(storage), 'system');
  assert.equal(storedLocale(storage), null);
  storeTheme(storage, 'dark');
  storeLocale(storage, 'de');
  // shared_preferences on the web: 'flutter.' + key, the value as JSON.
  assert.equal(items.get(THEME_KEY), '"dark"');
  assert.equal(items.get(LOCALE_KEY), '"de"');
  assert.equal(storedTheme(storage), 'dark');
  assert.equal(storedLocale(storage), 'de');
  storeTheme(storage, 'system');
  assert.equal(items.has(THEME_KEY), false);
  items.set(LOCALE_KEY, '"pt-BR"');
  assert.equal(storedLocale(storage), null);
  items.set(LOCALE_KEY, '"nl-BE"');
  assert.equal(storedLocale(storage), 'nl');
  items.set(THEME_KEY, 'not json');
  assert.equal(storedTheme(storage), 'system');
  assert.deepEqual(['system', 'light', 'dark'].map(nextTheme), ['light', 'dark', 'system']);
});

// Just enough DOM for renderHeader.
class Node {
  constructor(tag) {
    this.tagName = tag;
    this.children = [];
    this.attributes = {};
    this.listeners = {};
    this.parent = null;
    this.text = '';
  }
  setAttribute(k, v) {
    this.attributes[k] = String(v);
  }
  removeAttribute(k) {
    delete this.attributes[k];
  }
  appendChild(c) {
    c.parent = this;
    this.children.push(c);
    return c;
  }
  get firstChild() {
    return this.children[0] ?? null;
  }
  removeChild(c) {
    this.children = this.children.filter((x) => x !== c);
    return c;
  }
  addEventListener(t, fn) {
    (this.listeners[t] ??= []).push(fn);
  }
  click() {
    for (const fn of this.listeners.click ?? []) fn({});
  }
  get textContent() {
    return this.text + this.children.map((c) => c.textContent).join('');
  }
  *walk() {
    yield this;
    for (const c of this.children) yield* c.walk();
  }
}

function fakeWindow() {
  const document = {
    createElement: (t) => new Node(t),
    createElementNS: (_n, t) => new Node(t),
    createTextNode: (text) => Object.assign(new Node('#text'), { text }),
    documentElement: new Node('html'),
  };
  return { document };
}

test('the header links to the site in its language', () => {
  const w = fakeWindow();
  const header = renderHeader(w, { lang: 'de', theme: 'system' });
  const hrefs = [...header.element.walk()].map((n) => n.attributes.href).filter(Boolean);
  for (const href of [
    'https://velorki.com/de',
    'https://velorki.com/de/#features',
    'https://velorki.com/de/docs',
    'https://velorki.com/de/plus',
    'https://velorki.com/de/download',
    GITHUB_URL,
  ]) {
    assert.ok(hrefs.includes(href), href);
  }
  // The call to action is the site's "Get the app", to the download page.
  const pills = [...header.element.walk()].filter((n) => n.attributes.class === 'vh-btn');
  assert.ok(pills.length >= 1);
  for (const pill of pills) {
    assert.equal(pill.textContent, 'App holen');
    assert.equal(pill.attributes.href, 'https://velorki.com/de/download');
  }
  assert.equal(w.document.documentElement.attributes.lang, 'de');
  assert.equal(w.document.documentElement.attributes['data-theme'], undefined);
});

test('a pick in the header is shown and told; one from the app is only shown', () => {
  const w = fakeWindow();
  const picks = [];
  const header = renderHeader(w, {
    lang: 'en',
    theme: 'system',
    onTheme: (t) => picks.push(['theme', t]),
    onLanguage: (l) => picks.push(['lang', l]),
  });
  const buttons = () => [...header.element.walk()].filter((n) => n.tagName === 'button');
  buttons()
    .find((b) => b.attributes.title === 'Dark')
    .click();
  assert.equal(w.document.documentElement.attributes['data-theme'], 'dark');
  buttons()
    .find((b) => b.attributes.lang === 'it')
    .click();
  assert.equal(w.document.documentElement.attributes.lang, 'it');
  assert.ok(header.element.textContent.includes('Funzionalità'));
  assert.deepEqual(picks, [
    ['theme', 'dark'],
    ['lang', 'it'],
  ]);

  header.set({ theme: 'system', lang: 'nl' });
  assert.equal(w.document.documentElement.attributes['data-theme'], undefined);
  assert.ok(header.element.textContent.includes('Handleiding'));
  assert.equal(picks.length, 2);
});
