// SPDX-License-Identifier: AGPL-3.0-only
// The Plus prices per country, as the stores showed them when prices.json was
// last filled: by scripts/prices-stores.mjs at each deploy, or by
// scripts/prices-public.mjs from the public store pages.
import data from './prices.json';

export interface StorePrice {
  /** ISO 4217, the store's currency in that country. */
  currency: string;
  /** Decimal strings in that currency, tax included as the store shows it. */
  monthly: string;
  yearly: string;
}

export interface PriceTable {
  /** YYYY-MM-DD. */
  fetchedAt: string;
  source: string;
  appStore: Record<string, StorePrice>;
  googlePlay: Record<string, StorePrice>;
}

export const PRICES: PriceTable = data;

export type Store = 'appStore' | 'googlePlay';
export const STORES: readonly Store[] = ['appStore', 'googlePlay'];

/** Every country either store has a price for, sorted by code. */
export function pricedCountries(table: PriceTable): string[] {
  return [...new Set([...Object.keys(table.appStore), ...Object.keys(table.googlePlay)])].sort();
}

/** The country each site language shows prices for first. */
const LOCALE_COUNTRY: Record<string, string> = {
  en: 'US',
  de: 'DE',
  es: 'ES',
  fr: 'FR',
  it: 'IT',
  nl: 'NL',
};

/**
 * The country the price list opens on: the one the page's language most
 * likely means ("en" → US, "de" → DE). The browser's own languages are not
 * read, so the server and the browser show the same country.
 */
export function defaultCountry(pageLocale: string): string {
  return LOCALE_COUNTRY[pageLocale.split('-')[0] ?? ''] ?? 'US';
}

/** `amount` in `currency`, written the way `locale` writes money. */
export function formatPrice(amount: string, currency: string, locale: string): string {
  return new Intl.NumberFormat(locale, { style: 'currency', currency }).format(Number(amount));
}

/** "October 2026" for fetchedAt, in `locale`. */
export function formatAsOf(fetchedAt: string, locale: string): string {
  return new Intl.DateTimeFormat(locale, { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(
    new Date(`${fetchedAt}T00:00:00Z`),
  );
}

/** The country's name in `locale`, or its code. */
export function countryName(code: string, locale: string): string {
  try {
    return new Intl.DisplayNames([locale], { type: 'region' }).of(code) ?? code;
  } catch {
    return code;
  }
}

/** One country's prices, written out for display. */
export type ShownPrices = Partial<Record<Store, { monthly: string; yearly: string }>>;

/**
 * Everything the price list shows, written out in `locale` on the server: the
 * countries by name, sorted, and every price formatted. The browser only picks
 * from it, so its own Intl data (country names and money formats differ
 * between Node's and the browser's) never changes the text.
 */
export interface PriceView {
  initial: string;
  countries: { code: string; name: string }[];
  prices: Record<string, ShownPrices>;
}

export function priceView(table: PriceTable, locale: string): PriceView {
  const initial = defaultCountry(locale);
  const codes = pricedCountries(table);
  if (!codes.includes(initial)) codes.push(initial);
  const collator = new Intl.Collator(locale);
  const countries = codes
    .map((code) => ({ code, name: countryName(code, locale) }))
    .sort((a, b) => collator.compare(a.name, b.name));
  const prices: Record<string, ShownPrices> = {};
  for (const code of codes) {
    const shown: ShownPrices = {};
    for (const store of STORES) {
      const price = table[store][code];
      if (price) {
        shown[store] = {
          monthly: formatPrice(price.monthly, price.currency, locale),
          yearly: formatPrice(price.yearly, price.currency, locale),
        };
      }
    }
    prices[code] = shown;
  }
  return { initial, countries, prices };
}
