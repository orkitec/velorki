// SPDX-License-Identifier: AGPL-3.0-only
//
// What prices-public.mjs and prices-stores.mjs share: the store ids, the
// country table, the parsers for the public store pages and the store APIs'
// answers, and the writer for src/site/prices.json. Node built-ins only; the
// pure helpers are tested in test/prices.test.ts.

import { readFileSync, writeFileSync } from 'node:fs';

/** The App Store app (apps.apple.com/app/id…). */
export const APP_STORE_APP_ID = '6816790504';
/** The Google Play package. */
export const PLAY_PACKAGE = 'com.orkitec.velorki';
/**
 * The two Plus subscriptions: the same product ids in both stores (subscription
 * group "Velorki Plus" in App Store Connect), and on Play one base plan each.
 */
export const PRODUCTS = {
  monthly: { productId: 'plus_monthly', basePlanId: 'monthly' },
  yearly: { productId: 'plus_yearly', basePlanId: 'yearly' },
};

export const PRICES_FILE = new URL('../src/site/prices.json', import.meta.url);

/**
 * ISO 3166-1 alpha-3 → alpha-2, for App Store Connect, whose territories are
 * alpha-3 ids (plus XKS for Kosovo). Its values are also the list of countries
 * the public script asks both stores about.
 */
export const ALPHA3_TO_ALPHA2 = {
  ABW: 'AW', AFG: 'AF', AGO: 'AO', AIA: 'AI', ALA: 'AX', ALB: 'AL', AND: 'AD', ARE: 'AE', ARG: 'AR', ARM: 'AM',
  ASM: 'AS', ATG: 'AG', AUS: 'AU', AUT: 'AT', AZE: 'AZ', BDI: 'BI', BEL: 'BE', BEN: 'BJ', BES: 'BQ', BFA: 'BF',
  BGD: 'BD', BGR: 'BG', BHR: 'BH', BHS: 'BS', BIH: 'BA', BLM: 'BL', BLR: 'BY', BLZ: 'BZ', BMU: 'BM', BOL: 'BO',
  BRA: 'BR', BRB: 'BB', BRN: 'BN', BTN: 'BT', BWA: 'BW', CAF: 'CF', CAN: 'CA', CHE: 'CH', CHL: 'CL', CHN: 'CN',
  CIV: 'CI', CMR: 'CM', COD: 'CD', COG: 'CG', COK: 'CK', COL: 'CO', COM: 'KM', CPV: 'CV', CRI: 'CR', CUB: 'CU',
  CUW: 'CW', CYM: 'KY', CYP: 'CY', CZE: 'CZ', DEU: 'DE', DJI: 'DJ', DMA: 'DM', DNK: 'DK', DOM: 'DO', DZA: 'DZ',
  ECU: 'EC', EGY: 'EG', ERI: 'ER', ESP: 'ES', EST: 'EE', ETH: 'ET', FIN: 'FI', FJI: 'FJ', FLK: 'FK', FRA: 'FR',
  FRO: 'FO', FSM: 'FM', GAB: 'GA', GBR: 'GB', GEO: 'GE', GGY: 'GG', GHA: 'GH', GIB: 'GI', GIN: 'GN', GLP: 'GP',
  GMB: 'GM', GNB: 'GW', GNQ: 'GQ', GRC: 'GR', GRD: 'GD', GRL: 'GL', GTM: 'GT', GUF: 'GF', GUM: 'GU', GUY: 'GY',
  HKG: 'HK', HND: 'HN', HRV: 'HR', HTI: 'HT', HUN: 'HU', IDN: 'ID', IMN: 'IM', IND: 'IN', IRL: 'IE', IRN: 'IR',
  IRQ: 'IQ', ISL: 'IS', ISR: 'IL', ITA: 'IT', JAM: 'JM', JEY: 'JE', JOR: 'JO', JPN: 'JP', KAZ: 'KZ', KEN: 'KE',
  KGZ: 'KG', KHM: 'KH', KIR: 'KI', KNA: 'KN', KOR: 'KR', KWT: 'KW', LAO: 'LA', LBN: 'LB', LBR: 'LR', LBY: 'LY',
  LCA: 'LC', LIE: 'LI', LKA: 'LK', LSO: 'LS', LTU: 'LT', LUX: 'LU', LVA: 'LV', MAC: 'MO', MAF: 'MF', MAR: 'MA',
  MCO: 'MC', MDA: 'MD', MDG: 'MG', MDV: 'MV', MEX: 'MX', MHL: 'MH', MKD: 'MK', MLI: 'ML', MLT: 'MT', MMR: 'MM',
  MNE: 'ME', MNG: 'MN', MNP: 'MP', MOZ: 'MZ', MRT: 'MR', MSR: 'MS', MTQ: 'MQ', MUS: 'MU', MWI: 'MW', MYS: 'MY',
  MYT: 'YT', NAM: 'NA', NCL: 'NC', NER: 'NE', NGA: 'NG', NIC: 'NI', NIU: 'NU', NLD: 'NL', NOR: 'NO', NPL: 'NP',
  NRU: 'NR', NZL: 'NZ', OMN: 'OM', PAK: 'PK', PAN: 'PA', PER: 'PE', PHL: 'PH', PLW: 'PW', PNG: 'PG', POL: 'PL',
  PRI: 'PR', PRK: 'KP', PRT: 'PT', PRY: 'PY', PSE: 'PS', PYF: 'PF', QAT: 'QA', REU: 'RE', ROU: 'RO', RUS: 'RU',
  RWA: 'RW', SAU: 'SA', SDN: 'SD', SEN: 'SN', SGP: 'SG', SLB: 'SB', SLE: 'SL', SLV: 'SV', SMR: 'SM', SOM: 'SO',
  SPM: 'PM', SRB: 'RS', SSD: 'SS', STP: 'ST', SUR: 'SR', SVK: 'SK', SVN: 'SI', SWE: 'SE', SWZ: 'SZ', SXM: 'SX',
  SYC: 'SC', SYR: 'SY', TCA: 'TC', TCD: 'TD', TGO: 'TG', THA: 'TH', TJK: 'TJ', TKM: 'TM', TLS: 'TL', TON: 'TO',
  TTO: 'TT', TUN: 'TN', TUR: 'TR', TUV: 'TV', TWN: 'TW', TZA: 'TZ', UGA: 'UG', UKR: 'UA', URY: 'UY', USA: 'US',
  UZB: 'UZ', VAT: 'VA', VCT: 'VC', VEN: 'VE', VGB: 'VG', VIR: 'VI', VNM: 'VN', VUT: 'VU', WLF: 'WF', WSM: 'WS',
  XKS: 'XK', YEM: 'YE', ZAF: 'ZA', ZMB: 'ZM', ZWE: 'ZW',
};

/** Every alpha-2 country in the table, sorted. */
export const COUNTRIES = [...new Set(Object.values(ALPHA3_TO_ALPHA2))].sort();

/** How many fraction digits `currency` has, by Intl (JPY 0, EUR 2, KWD 3). */
export function fractionDigits(currency) {
  try {
    return new Intl.NumberFormat('en', { style: 'currency', currency }).resolvedOptions().maximumFractionDigits;
  } catch {
    return 2;
  }
}

const NATIVE_DIGITS = /[\u0660-\u0669\u06f0-\u06f9]/g;

/**
 * The amount in a store's localised price text, as a plain decimal string:
 * "34,99 €" → "34.99", "$3.99" → "3.99", "¥6,800" → "6800", "CHF 33.00" →
 * "33.00", "Rp 59.000" → "59000", "1.234,56 kr" → "1234.56". A separator
 * followed by exactly three digits is a thousands separator unless the
 * currency itself has three fraction digits. Null when there is no number.
 */
export function parseAmount(text, currency) {
  if (typeof text !== 'string') return null;
  const latin = text
    .replace(NATIVE_DIGITS, (d) => String(d.charCodeAt(0) & 0xf))
    .replace(/\u066b/g, '.')
    .replace(/\u066c/g, ',');
  const match = latin.match(/\d(?:[\d.,'\u2019 \u00a0\u202f]*\d)?/);
  if (!match) return null;
  // Spaces and apostrophes only ever group.
  const raw = match[0].replace(/['\u2019 \u00a0\u202f]/g, '');
  const seps = [...raw.matchAll(/[.,]/g)];
  if (seps.length === 0) return raw;
  const last = seps[seps.length - 1];
  const lastIndex = last.index ?? 0;
  const after = raw.length - lastIndex - 1;
  const sameKind = seps.filter((s) => s[0] === last[0]).length;
  let decimal;
  if (seps.some((s) => s[0] !== last[0])) decimal = true; // "1,234.56", "1.234,56"
  else if (sameKind > 1) decimal = false; // "1,234,567"
  else decimal = after !== 3 || fractionDigits(currency) === 3;
  if (!decimal) return raw.replace(/[.,]/g, '');
  return `${raw.slice(0, lastIndex).replace(/[.,]/g, '')}.${raw.slice(lastIndex + 1)}`;
}

/** The `priceCurrency` of the app's schema.org offer (the storefront's currency). */
export function offerCurrency(html) {
  const match = html.match(/"priceCurrency"\s*:\s*"([A-Z]{3})"/);
  return match ? match[1] : null;
}

const MONTHLY_WORDS = /month|monat|mensu|mois|maand|mese|mês|mies|måned|månad|kuukau|měsí|月|월/i;
const YEARLY_WORDS = /year|jähr|jahr|annu|anua|anno|jaar|ano|rok|år|vuosi|年|년/i;

/**
 * Splits two store items into monthly and yearly by price: the yearly plan is
 * always the dearer of the two. When the items' names say which is which
 * ("Velorki Plus monatlich"), they must agree, or this throws.
 */
export function pickMonthlyYearly(items) {
  if (items.length !== 2) return null;
  const [a, b] = items;
  if (!a || !b || Number(a.amount) === Number(b.amount)) return null;
  const [monthly, yearly] = Number(a.amount) < Number(b.amount) ? [a, b] : [b, a];
  if (monthly.name && yearly.name) {
    const reversed =
      (YEARLY_WORDS.test(monthly.name) && !MONTHLY_WORDS.test(monthly.name)) ||
      (MONTHLY_WORDS.test(yearly.name) && !YEARLY_WORDS.test(yearly.name));
    if (reversed) throw new Error(`names disagree with prices: "${monthly.name}" < "${yearly.name}"`);
  }
  return { monthly: monthly.amount, yearly: yearly.amount };
}

/** Every object in `value` whose `$kind` is `kind`, depth first. */
function* objectsOfKind(value, kind) {
  if (Array.isArray(value)) {
    for (const item of value) yield* objectsOfKind(item, kind);
  } else if (value && typeof value === 'object') {
    if (value.$kind === kind) yield value;
    for (const child of Object.values(value)) yield* objectsOfKind(child, kind);
  }
}

/**
 * An apps.apple.com app page → { currency, monthly, yearly }, or null when the
 * page lists no Plus purchases (Apple leaves the list out in some
 * storefronts). Reads the page's own JSON (`serialized-server-data`): the
 * "In-App Purchases" annotation holds one `textPair` per product, the name
 * (localised: "Velorki Plus jährlich") and the price ("34,99 €").
 */
export function parseAppStorePage(html) {
  const currency = offerCurrency(html);
  const blob = html.match(/<script[^>]*id="serialized-server-data"[^>]*>([\s\S]*?)<\/script>/);
  if (!currency || !blob) return null;
  const data = JSON.parse(blob[1]);
  for (const annotation of objectsOfKind(data, 'Annotation')) {
    const pairs = (annotation.items ?? []).filter(
      (item) => item?.$kind === 'textPair' && /Plus/.test(item.leadingText ?? ''),
    );
    if (pairs.length === 0) continue;
    const items = pairs.map((pair) => ({ name: pair.leadingText, amount: parseAmount(pair.trailingText, currency) }));
    if (items.some((item) => item.amount === null)) return null;
    const picked = pickMonthlyYearly(items);
    return picked ? { currency, ...picked } : null;
  }
  return null;
}

/**
 * A play.google.com details page (hl=en) → { currency, monthly, yearly }, or
 * null. Play shows only a range over all in-app products, "$3.99 - $34.99 per
 * item" (in the EEA "… if billed through Play"); with exactly two Plus
 * products the lower end is the monthly and the upper the yearly price.
 */
export function parsePlayPage(html) {
  const currency = offerCurrency(html);
  const range = html.match(/"([^"[\]]{1,40}?) - ([^"[\]]{1,40}?) (?:per item|if billed through Play)"/);
  if (!currency || !range) return null;
  const low = parseAmount(range[1], currency);
  const high = parseAmount(range[2], currency);
  if (low === null || high === null || Number(low) >= Number(high)) return null;
  return { currency, monthly: low, yearly: high };
}

/** A Google money value ({ units, nanos }) as a decimal string. */
export function googleMoney(price) {
  const units = BigInt(price.units ?? '0');
  const nanos = Number(price.nanos ?? 0);
  if (nanos === 0) return units.toString();
  const fraction = String(Math.abs(nanos)).padStart(9, '0').replace(/0+$/, '');
  const negative = units < 0n || nanos < 0;
  return `${negative ? '-' : ''}${(units < 0n ? -units : units).toString()}.${fraction}`;
}

/**
 * monetization.subscriptions.get for both products → { <CC>: { currency,
 * monthly, yearly } }, from each product's base plan's regional configs.
 * Countries where either plan has no price are left out.
 */
export function playPricesFromSubscriptions(monthlySub, yearlySub) {
  const byRegion = (sub, basePlanId) => {
    const plan = (sub.basePlans ?? []).find((p) => p.basePlanId === basePlanId);
    const out = new Map();
    for (const config of plan?.regionalConfigs ?? []) {
      if (config.price?.currencyCode) out.set(config.regionCode, config.price);
    }
    return out;
  };
  const monthly = byRegion(monthlySub, PRODUCTS.monthly.basePlanId);
  const yearly = byRegion(yearlySub, PRODUCTS.yearly.basePlanId);
  const result = {};
  for (const [region, m] of monthly) {
    const y = yearly.get(region);
    if (!y || y.currencyCode !== m.currencyCode) continue;
    result[region] = { currency: m.currencyCode, monthly: googleMoney(m), yearly: googleMoney(y) };
  }
  return sortKeys(result);
}

/**
 * The current price per territory from App Store Connect's
 * /v1/subscriptions/{id}/prices pages (with the price points and territories
 * included): the entry with the latest startDate not after `today` (a null
 * startDate is the original price). → Map<CC, { currency, amount }>.
 */
export function ascCurrentPrices(pages, today) {
  const points = new Map();
  const territories = new Map();
  const prices = [];
  for (const page of pages) {
    prices.push(...(page.data ?? []));
    for (const item of page.included ?? []) {
      if (item.type === 'subscriptionPricePoints') points.set(item.id, item.attributes?.customerPrice);
      if (item.type === 'territories') territories.set(item.id, item.attributes?.currency);
    }
  }
  const best = new Map();
  for (const price of prices) {
    const start = price.attributes?.startDate ?? '';
    if (start > today) continue;
    const territory = price.relationships?.territory?.data?.id;
    const point = price.relationships?.subscriptionPricePoint?.data?.id;
    if (!territory || !point) continue;
    const seen = best.get(territory);
    if (seen && seen.start >= start) continue;
    best.set(territory, { start, point });
  }
  const result = new Map();
  for (const [territory, { point }] of best) {
    const cc = ALPHA3_TO_ALPHA2[territory];
    const amount = points.get(point);
    const currency = territories.get(territory);
    if (cc && amount && currency) result.set(cc, { currency, amount });
  }
  return result;
}

/** Joins the monthly and yearly maps of ascCurrentPrices into the file's shape. */
export function joinAsc(monthly, yearly) {
  const result = {};
  for (const [cc, m] of monthly) {
    const y = yearly.get(cc);
    if (!y || y.currency !== m.currency) continue;
    result[cc] = { currency: m.currency, monthly: m.amount, yearly: y.amount };
  }
  return sortKeys(result);
}

export function sortKeys(object) {
  return Object.fromEntries(Object.entries(object).sort(([a], [b]) => a.localeCompare(b)));
}

export function readPrices() {
  return JSON.parse(readFileSync(PRICES_FILE, 'utf8'));
}

export function writePrices({ source, appStore, googlePlay }) {
  const file = {
    fetchedAt: new Date().toISOString().slice(0, 10),
    source,
    appStore: sortKeys(appStore),
    googlePlay: sortKeys(googlePlay),
  };
  writeFileSync(PRICES_FILE, `${JSON.stringify(file, null, 2)}\n`);
  return file;
}
