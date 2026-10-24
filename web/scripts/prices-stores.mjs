// SPDX-License-Identifier: AGPL-3.0-only
//
// Refreshes src/site/prices.json from the stores' own APIs, with the accounts
// the release already uses. Run by web-deploy.yml before the build:
//
//   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8_BASE64   App Store Connect API key
//   PLAY_SERVICE_ACCOUNT_JSON                       Google Play service account
//
// App Store Connect: the app's subscription groups → the Plus subscriptions by
// product id → /v1/subscriptions/{id}/prices with each price point's
// customerPrice and each territory's currency; per territory the price whose
// startDate is the latest one not in the future.
// Google Play: monetization.subscriptions.get per product → the base plan's
// regionalConfigs[].price.
//
// It never fails the deploy: on a missing variable, a refused key or a network
// error it says what is wrong (for a 403, which permission is missing), leaves
// the committed file as it is and exits 0. Only when both stores answered does
// it write the file, and then it sets `written=true` in $GITHUB_OUTPUT. It
// never prints a key or a token. The API clients are in prices-api.mjs.

import { appendFileSync } from 'node:fs';
import { PRODUCTS, playPricesFromSubscriptions, writePrices } from './prices-lib.mjs';
import { StoreError, appStorePrices, playSession } from './prices-api.mjs';

const SOURCE =
  'Store APIs at deploy (scripts/prices-stores.mjs). App Store Connect: the current price per ' +
  'territory of the subscriptions plus_monthly and plus_yearly. Google Play: the regional prices ' +
  'of the base plans plus_monthly:monthly and plus_yearly:yearly. Prices as the stores charge ' +
  'them, tax included where the store includes it.';

async function googlePlayPrices() {
  const call = await playSession();
  const monthly = await call('GET', `/subscriptions/${PRODUCTS.monthly.productId}`);
  const yearly = await call('GET', `/subscriptions/${PRODUCTS.yearly.productId}`);
  return playPricesFromSubscriptions(monthly, yearly);
}

// ---------------------------------------------------------------------------

async function attempt(name, fetchPrices) {
  try {
    const prices = await fetchPrices();
    const count = Object.keys(prices).length;
    if (count === 0) throw new StoreError('no country has both a monthly and a yearly price');
    console.log(`prices: ${name}: ${count} countries`);
    return prices;
  } catch (error) {
    const message = error instanceof StoreError ? error.message : `unexpected error (${String(error)})`;
    console.log(`::warning::prices: ${name}: ${message}`);
    return null;
  }
}

const appStore = await attempt('App Store Connect', appStorePrices);
const googlePlay = await attempt('Google Play', googlePlayPrices);

if (!appStore || !googlePlay) {
  console.log('prices: src/site/prices.json left as committed');
} else {
  const file = writePrices({ source: SOURCE, appStore, googlePlay });
  for (const cc of ['DE', 'US', 'GB']) {
    const a = file.appStore[cc];
    const g = file.googlePlay[cc];
    if (a) console.log(`prices: App Store ${cc}: ${a.currency} ${a.monthly} / ${a.yearly}`);
    if (g) console.log(`prices: Google Play ${cc}: ${g.currency} ${g.monthly} / ${g.yearly}`);
  }
  console.log(`prices: wrote src/site/prices.json (${file.fetchedAt})`);
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, 'written=true\n');
}
