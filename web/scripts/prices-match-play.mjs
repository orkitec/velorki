// SPDX-License-Identifier: AGPL-3.0-only
//
// Sets the Google Play prices of Velorki Plus to the App Store's, country by
// country, so nobody has to click through every region in Play Console. Run
// by .github/workflows/play-prices.yml, where the keys are:
//
//   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8_BASE64   App Store Connect API key
//   PLAY_SERVICE_ACCOUNT_JSON                       Google Play service account
//
//   node scripts/prices-match-play.mjs            dry run: the table, nothing sent
//   node scripts/prices-match-play.mjs --apply    patch the base plans
//   node scripts/prices-match-play.mjs --offline  dry run from src/site/prices.json
//                                                 alone (no keys; Play's prices there
//                                                 stand in for the base plans)
//
// The App Store side is App Store Connect's current price per territory, or,
// when the ASC key is missing or refused, the appStore section of
// src/site/prices.json (it says so). The Play side is monetization.subscriptions
// .get for plus_monthly and plus_yearly, base plans monthly and yearly. A Play
// region gets Apple's price when the App Store charges in the same currency
// there; every other region is left alone (rules and checks: prices-match.mjs).
//
// --apply sends one monetization.subscriptions.patch per product that changes,
// `updateMask=basePlans` with the subscription as read and only the matched
// regionalConfigs[].price replaced, at the regions version Google's
// convertRegionPrices reports. A base plan's new price applies to new
// subscribers only: existing ones stay in their legacy price cohort until
// basePlans.migratePrices moves them, which this never calls.
//
// It never prints a key or a token. With $GITHUB_STEP_SUMMARY set it also
// writes the table there.

import { appendFileSync } from 'node:fs';
import { PRODUCTS, readPrices } from './prices-lib.mjs';
import { StoreError, appStorePrices, missingAscEnv, playSession } from './prices-api.mjs';
import { checkLimits, decimalToNanos, markdownTable, matchPlayToApple, moneyToNanos, summarise, toGoogleMoney, withTargets } from './prices-match.mjs';

const PLAY_WRITE_FORBIDDEN =
  'the service account may not edit this app\'s subscriptions; in Play Console → Users and ' +
  'permissions → the service account → App permissions → Velorki it needs "Manage store ' +
  'presence" (beside "View app information (read-only)")';
const CONVERT_FORBIDDEN =
  'the service account may not use convertRegionPrices; in Play Console it needs "View app ' +
  'information (read-only)" for this app';
/** Google's ceiling for a price: US$999.99 or the local equivalent, US$400 in South Korea. */
const CEILINGS_USD = { default: '999.99', KR: '400' };
/** What patch takes when convertRegionPrices cannot say (the first regions version). */
const FALLBACK_REGIONS_VERSION = '2022/02';

const args = new Set(process.argv.slice(2));
const unknown = [...args].filter((arg) => !['--apply', '--offline', '--help', '-h'].includes(arg));
if (args.has('--help') || args.has('-h') || unknown.length > 0) {
  if (unknown.length > 0) console.error(`prices-match-play: unknown option ${unknown.join(', ')}`);
  console.error('usage: node scripts/prices-match-play.mjs [--apply | --offline]');
  process.exit(unknown.length > 0 ? 2 : 0);
}
const apply = args.has('--apply');
const offline = args.has('--offline');
if (apply && offline) {
  console.error('prices-match-play: --offline is a dry run; it cannot --apply');
  process.exit(2);
}

const summaryLines = [];
const say = (line = '') => {
  console.log(line);
  summaryLines.push(line);
};
function fail(message) {
  console.error(`::error::prices-match-play: ${message}`);
  summaryLines.push(`**Failed:** ${message}`);
  flushSummary();
  process.exit(1);
}
function flushSummary() {
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${summaryLines.join('\n')}\n`);
}

say(`## Google Play prices → App Store (${apply ? 'apply' : 'dry run'})`);
say();

// --- App Store -------------------------------------------------------------

const committed = readPrices();
let apple;
const missingAsc = missingAscEnv();
if (!offline && missingAsc.length === 0) {
  try {
    apple = await appStorePrices();
    say(`App Store: ${Object.keys(apple).length} countries from App Store Connect.`);
  } catch (error) {
    if (!(error instanceof StoreError)) throw error;
    console.log(`::warning::App Store Connect: ${error.message}`);
    say(`App Store Connect unavailable (${error.message}).`);
  }
} else if (!offline) {
  say(`App Store Connect not asked: ${missingAsc.join(', ')} not set.`);
}
if (!apple) {
  apple = committed.appStore;
  say(
    `App Store: ${Object.keys(apple).length} countries from the committed src/site/prices.json ` +
      `(fetched ${committed.fetchedAt}), not from App Store Connect.`,
  );
}

// --- Google Play -----------------------------------------------------------

/** prices.json's googlePlay section dressed up as two subscriptions.get answers. */
function subscriptionsFromFile(googlePlay) {
  const out = {};
  for (const [period, { productId, basePlanId }] of Object.entries(PRODUCTS)) {
    const regionalConfigs = Object.entries(googlePlay).map(([regionCode, prices]) => ({
      regionCode,
      price: toGoogleMoney(prices.currency, prices[period]),
    }));
    out[period] = { productId, basePlans: [{ basePlanId, regionalConfigs }] };
  }
  return out;
}

let call = null;
let subscriptions;
if (offline) {
  subscriptions = subscriptionsFromFile(committed.googlePlay);
  say(`Google Play: the committed prices.json's googlePlay section stands in (offline; nothing asked or sent).`);
} else {
  try {
    call = await playSession();
    subscriptions = {};
    for (const [period, { productId }] of Object.entries(PRODUCTS)) {
      subscriptions[period] = await call('GET', `/subscriptions/${productId}`);
    }
  } catch (error) {
    if (!(error instanceof StoreError)) throw error;
    if (/missing PLAY_SERVICE_ACCOUNT_JSON/.test(error.message)) {
      fail(
        'PLAY_SERVICE_ACCOUNT_JSON is not set. It is the JSON key of the Play service account and lives ' +
          'only in the GitHub environment `release`: run Actions → play prices → Run workflow, or export ' +
          'it locally (with ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8_BASE64 for live App Store prices). ' +
          '`--offline` shows the table from src/site/prices.json alone.',
      );
    }
    fail(`Google Play: ${error.message}`);
  }
}

// --- Google's ceiling and regions version ----------------------------------

const ceilings = {};
let regionsVersion = FALLBACK_REGIONS_VERSION;
if (call) {
  try {
    for (const [scope, usd] of Object.entries(CEILINGS_USD)) {
      const nanos = decimalToNanos(usd) ?? 0n;
      const answer = await call(
        'POST',
        '/pricing:convertRegionPrices',
        { price: { currencyCode: 'USD', units: (nanos / 1_000_000_000n).toString(), nanos: Number(nanos % 1_000_000_000n) } },
        CONVERT_FORBIDDEN,
      );
      if (answer.regionVersion?.version) regionsVersion = answer.regionVersion.version;
      for (const [region, converted] of Object.entries(answer.convertedRegionPrices ?? {})) {
        if (scope !== 'default' && region !== scope) continue;
        if (scope === 'default' && region in CEILINGS_USD) continue;
        if (converted.price?.currencyCode) ceilings[region] = moneyToNanos(converted.price);
      }
    }
  } catch (error) {
    if (!(error instanceof StoreError)) throw error;
    if (apply) fail(`Google Play: cannot check prices against Google's ceiling: ${error.message}`);
    say(`Google's ceiling not checked (${error.message}).`);
  }
}

// --- Match, check, show ----------------------------------------------------

let rows;
try {
  rows = checkLimits(matchPlayToApple(subscriptions, apple), ceilings);
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}
const counts = summarise(rows);
say();
say(markdownTable(rows));
say();
say(
  `**${counts.update} to change**, ${counts.same} already the App Store's price, ` +
    `${counts.currency} in another currency than the App Store's (unchanged), ` +
    `${counts.missing} without an App Store price (unchanged), ${counts.blocked} blocked by the checks.`,
);
if (counts.blocked > 0) console.log(`::warning::${counts.blocked} price(s) failed the checks and are not sent`);

// --- Apply -----------------------------------------------------------------

if (!apply) {
  say();
  say(counts.update > 0 ? 'Dry run: nothing sent. Run with `--apply` (the workflow input `apply`) to set these.' : 'Dry run: nothing to send.');
  flushSummary();
  process.exit(0);
}

say();
const updated = [];
for (const [period, { productId, basePlanId }] of Object.entries(PRODUCTS)) {
  const changes = rows.filter((row) => row.period === period && row.status === 'update').length;
  if (changes === 0) {
    say(`${productId}:${basePlanId}: nothing to change.`);
    continue;
  }
  const body = withTargets(subscriptions[period], basePlanId, rows);
  const query = new URLSearchParams({ updateMask: 'basePlans', 'regionsVersion.version': regionsVersion });
  try {
    await call('PATCH', `/subscriptions/${productId}?${query}`, body, PLAY_WRITE_FORBIDDEN);
  } catch (error) {
    if (!(error instanceof StoreError)) throw error;
    const done = updated.length > 0 ? ` (${updated.join(', ')} already updated)` : '';
    fail(`${productId}:${basePlanId}: ${error.message}${done}`);
  }
  updated.push(`${productId}:${basePlanId}`);
  say(`${productId}:${basePlanId}: ${changes} region(s) updated (regions version ${regionsVersion}); new subscribers only.`);
}
flushSummary();
