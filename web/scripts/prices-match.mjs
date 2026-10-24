// SPDX-License-Identifier: AGPL-3.0-only
//
// The pure half of prices-match-play.mjs: which Google Play regional price of
// a Plus base plan should become the App Store's price, the Money values the
// Play API takes, the checks before anything is sent, and the table. Node
// built-ins only; tested in test/prices-match.test.ts.
//
// The rule: a Play region whose currency is the App Store's currency in that
// country gets Apple's price, exactly. Every other region (another currency,
// or no App Store price there) is left as it is.

import { PRODUCTS, fractionDigits, googleMoney } from './prices-lib.mjs';

const NANOS = 1_000_000_000n;

/** A decimal string ("3.99", "1234", "-0.5") → BigInt nanos, or null. */
export function decimalToNanos(text) {
  const match = /^(-?)(\d+)(?:\.(\d+))?$/.exec(String(text).trim());
  if (!match) return null;
  const [, sign, whole, fraction = ''] = match;
  // Beyond nine digits only rounding is left: half up on the tenth.
  let nanos = BigInt(whole) * NANOS + BigInt(fraction.slice(0, 9).padEnd(9, '0'));
  if (fraction.length > 9 && Number(fraction[9]) >= 5) nanos += 1n;
  return sign ? -nanos : nanos;
}

/** A Google Money value → BigInt nanos. */
export function moneyToNanos(price) {
  return decimalToNanos(googleMoney(price));
}

/**
 * Rounds a decimal amount to `currency`'s minor unit (half up: EUR 3.995 →
 * 4.00, JPY 499.5 → 500) → Money { currencyCode, units, nanos }, or null when
 * the amount is no decimal number. Positive amounts only make sense here.
 */
export function toGoogleMoney(currency, amount) {
  const nanos = decimalToNanos(amount);
  if (nanos === null) return null;
  const step = 10n ** BigInt(9 - Math.min(fractionDigits(currency), 9));
  const rounded = ((nanos + step / 2n) / step) * step;
  return { currencyCode: currency, units: (rounded / NANOS).toString(), nanos: Number(rounded % NANOS) };
}

/** Money → "3.99" in the currency's own digits (JPY "500", EUR "4.00"). */
export function formatMoney(price) {
  const digits = fractionDigits(price.currencyCode);
  const nanos = moneyToNanos(price) ?? 0n;
  const scale = 10n ** BigInt(9 - Math.min(digits, 9));
  const minor = (nanos + scale / 2n) / scale;
  if (digits === 0) return minor.toString();
  const text = minor.toString().padStart(digits + 1, '0');
  return `${text.slice(0, -digits)}.${text.slice(-digits)}`;
}

/** The base plan `basePlanId` of a monetization.subscriptions resource. */
function basePlan(subscription, basePlanId) {
  return (subscription.basePlans ?? []).find((plan) => plan.basePlanId === basePlanId);
}

/**
 * One row per Play region of each base plan: { region, productId,
 * basePlanId, period, currency, current (Money), target (Money | null),
 * status, note }. `status`:
 *   update    the App Store charges another amount in this currency
 *   same      Play already charges Apple's price
 *   currency  the App Store charges in another currency here: unchanged
 *   missing   the App Store has no price here: unchanged
 * `apple` is prices.json's shape, { <CC>: { currency, monthly, yearly } };
 * `subscriptions` is { monthly, yearly } of subscriptions.get answers.
 */
export function matchPlayToApple(subscriptions, apple) {
  const rows = [];
  for (const [period, { productId, basePlanId }] of Object.entries(PRODUCTS)) {
    const subscription = subscriptions[period];
    const plan = subscription && basePlan(subscription, basePlanId);
    if (!plan) throw new Error(`Play subscription ${productId} has no base plan ${basePlanId}`);
    for (const config of plan.regionalConfigs ?? []) {
      const current = config.price;
      if (!current?.currencyCode) continue;
      const row = {
        region: config.regionCode,
        productId,
        basePlanId,
        period,
        currency: current.currencyCode,
        current,
        target: null,
        status: 'missing',
        note: 'no App Store price here',
      };
      const theirs = apple[config.regionCode];
      const amount = theirs?.[period];
      if (theirs && amount) {
        if (theirs.currency !== current.currencyCode) {
          row.status = 'currency';
          row.note = `App Store charges ${theirs.currency} ${amount} here`;
        } else {
          const target = toGoogleMoney(theirs.currency, amount);
          if (!target) throw new Error(`App Store price "${amount}" in ${config.regionCode} is not a number`);
          row.target = target;
          const same = moneyToNanos(target) === moneyToNanos(current);
          row.status = same ? 'same' : 'update';
          row.note = same ? "already the App Store's price" : "→ App Store's price";
        }
      }
      rows.push(row);
    }
  }
  return rows.sort((a, b) => a.region.localeCompare(b.region) || a.period.localeCompare(b.period));
}

/**
 * The checks before a row is sent; a row that fails turns `blocked` with the
 * reason, and is not sent. Google documents a ceiling (US$999.99 or the local
 * equivalent, US$400 in South Korea) but no floor and no API for either, so:
 *   - the target must be above zero and in the currency's minor unit;
 *   - it must not exceed `ceilings[region]` (BigInt nanos in the region's
 *     currency; prices-match-play.mjs gets them from convertRegionPrices) when
 *     that region has one;
 *   - it must lie within half and twice the current Play price: Plus costs
 *     about the same in both stores, so anything further off is more likely
 *     a wrong unit or currency than a price, and is better set by hand.
 * Google itself rejects a price under its floor with a 400 naming the region.
 * @param {ReturnType<typeof matchPlayToApple>} rows
 * @param {Record<string, bigint | null>} [ceilings]
 */
export function checkLimits(rows, ceilings = {}) {
  for (const row of rows) {
    if (row.status !== 'update' || !row.target) continue;
    const target = moneyToNanos(row.target) ?? 0n;
    const current = moneyToNanos(row.current) ?? 0n;
    const step = 10n ** BigInt(9 - Math.min(fractionDigits(row.currency), 9));
    let reason = null;
    if (target <= 0n) reason = 'not above zero';
    else if (target % step !== 0n) reason = `not in ${row.currency}'s minor unit`;
    else if (ceilings[row.region] != null && target > ceilings[row.region]) {
      reason = `above Google's ceiling here (${formatMoney({ currencyCode: row.currency, ...splitNanos(ceilings[row.region]) })})`;
    } else if (current > 0n && (target * 2n < current || target > current * 2n)) {
      reason = 'more than twice or under half the current Play price; set it by hand if meant';
    }
    if (reason) {
      row.status = 'blocked';
      row.note = `not sent: ${reason}`;
    }
  }
  return rows;
}

function splitNanos(nanos) {
  return { units: (nanos / NANOS).toString(), nanos: Number(nanos % NANOS) };
}

/**
 * A copy of `subscription` whose base plan `basePlanId` charges each row's
 * target where the row's status is `update`. Nothing else changes.
 * @template T
 * @param {T} subscription
 * @param {string} basePlanId
 * @param {ReturnType<typeof matchPlayToApple>} rows
 * @returns {T}
 */
export function withTargets(subscription, basePlanId, rows) {
  const copy = structuredClone(subscription);
  const plan = basePlan(copy, basePlanId);
  if (!plan) throw new Error(`no base plan ${basePlanId}`);
  const targets = new Map(
    rows.filter((row) => row.basePlanId === basePlanId && row.status === 'update').map((row) => [row.region, row.target]),
  );
  for (const config of plan.regionalConfigs ?? []) {
    const target = targets.get(config.regionCode);
    if (target) config.price = { ...target };
  }
  return copy;
}

/** Counts per status. */
export function summarise(rows) {
  const counts = { update: 0, same: 0, currency: 0, missing: 0, blocked: 0 };
  for (const row of rows) counts[row.status] += 1;
  return counts;
}

/** The rows as a Markdown table (the terminal and $GITHUB_STEP_SUMMARY alike). */
export function markdownTable(rows) {
  const lines = ['| Region | Currency | Base plan | Play now | Target | Note |', '|---|---|---|---|---|---|'];
  for (const row of rows) {
    const target = row.target && row.status !== 'same' ? formatMoney(row.target) : '';
    lines.push(
      `| ${row.region} | ${row.currency} | ${row.productId}:${row.basePlanId} | ${formatMoney(row.current)} | ${target} | ${row.note} |`,
    );
  }
  return lines.join('\n');
}
