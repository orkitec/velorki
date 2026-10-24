// SPDX-License-Identifier: AGPL-3.0-only
//
// Fills src/site/prices.json from the public store pages, for when the store
// APIs (prices-stores.mjs, run at deploy) are not at hand:
//
//   node scripts/prices-public.mjs            # every country
//   node scripts/prices-public.mjs DE US CH   # just these, merged into the file
//
// Politely: one request at a time, about one a second, with a real
// User-Agent. Roughly eight minutes for every country in both stores.
//
// App Store: apps.apple.com/<cc>/app/id… lists the in-app purchases with their
// localised names and prices; a country without a storefront redirects to
// another one and is skipped, as is a storefront that lists no purchases.
// Google Play: the details page shows only the range over all products ("$3.99
// - $34.99 per item"); while Plus has exactly two products, the low end is the
// monthly and the high end the yearly price. A country where the app is not
// offered shows no range and is skipped.

import {
  APP_STORE_APP_ID,
  COUNTRIES,
  PLAY_PACKAGE,
  parseAppStorePage,
  parsePlayPage,
  readPrices,
  writePrices,
} from './prices-lib.mjs';

const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
const PAUSE_MS = 1000;

const SOURCE =
  'Public store pages (scripts/prices-public.mjs). App Store: the in-app purchases listed on ' +
  'apps.apple.com per storefront, the cheaper one monthly. Google Play: the "per item" range on ' +
  'play.google.com per country, low end monthly and high end yearly, valid while Plus has exactly ' +
  'two products. Prices as the stores show them, tax included where the store includes it.';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function get(url) {
  const response = await fetch(url, {
    headers: { 'user-agent': USER_AGENT, 'accept-language': 'en' },
    redirect: 'follow',
  });
  return { status: response.status, url: response.url, html: response.ok ? await response.text() : '' };
}

async function appStore(cc) {
  const page = await get(`https://apps.apple.com/${cc.toLowerCase()}/app/id${APP_STORE_APP_ID}`);
  if (page.status !== 200) return { skip: `HTTP ${page.status}` };
  // No storefront for this country: Apple redirects to another one.
  if (!new URL(page.url).pathname.startsWith(`/${cc.toLowerCase()}/`)) return { skip: 'no storefront' };
  const prices = parseAppStorePage(page.html);
  return prices ? { prices } : { skip: 'no purchases listed' };
}

async function googlePlay(cc) {
  const page = await get(`https://play.google.com/store/apps/details?id=${PLAY_PACKAGE}&gl=${cc}&hl=en`);
  if (page.status !== 200) return { skip: `HTTP ${page.status}` };
  const prices = parsePlayPage(page.html);
  return prices ? { prices } : { skip: 'no price range' };
}

const only = process.argv.slice(2).map((cc) => cc.toUpperCase());
const countries = only.length > 0 ? only : COUNTRIES;
// A partial run merges into what is there; a full run replaces it.
const previous = only.length > 0 ? readPrices() : { appStore: {}, googlePlay: {} };
const result = { appStore: { ...previous.appStore }, googlePlay: { ...previous.googlePlay } };

for (const [store, fetchOne] of [
  ['appStore', appStore],
  ['googlePlay', googlePlay],
]) {
  let found = 0;
  for (const cc of countries) {
    let outcome;
    try {
      outcome = await fetchOne(cc);
    } catch (error) {
      outcome = { skip: error instanceof Error ? error.message : String(error) };
    }
    if (outcome.prices) {
      result[store][cc] = outcome.prices;
      found += 1;
      console.log(`${store} ${cc}: ${outcome.prices.currency} ${outcome.prices.monthly} / ${outcome.prices.yearly}`);
    } else {
      delete result[store][cc];
      console.log(`${store} ${cc}: skipped (${outcome.skip})`);
    }
    await sleep(PAUSE_MS);
  }
  console.log(`${store}: ${found} of ${countries.length} countries`);
}

const file = writePrices({ source: SOURCE, ...result });
console.log(
  `wrote src/site/prices.json: ${Object.keys(file.appStore).length} App Store, ` +
    `${Object.keys(file.googlePlay).length} Google Play countries`,
);
