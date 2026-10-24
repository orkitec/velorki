// SPDX-License-Identifier: AGPL-3.0-only
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { PlusPrices } from '@/components/PlusPrices';
import { priceLines } from '@/site/llms';
import { PRICES, defaultCountry, formatAsOf, formatPrice, priceView, pricedCountries, type PriceTable } from '@/site/prices';
import {
  ascCurrentPrices,
  googleMoney,
  joinAsc,
  parseAmount,
  parseAppStorePage,
  parsePlayPage,
  pickMonthlyYearly,
  playPricesFromSubscriptions,
} from '../scripts/prices-lib.mjs';

/** A cut-down apps.apple.com page: the schema.org offer and the page's JSON. */
function appStorePage(currency: string, items: Array<[string, string]>): string {
  const data = {
    data: [
      {
        information: {
          items: [
            { $kind: 'Annotation', title: 'Size', summary: '52 MB', items: [] },
            {
              $kind: 'Annotation',
              title: 'In-App Purchases',
              summary: 'Yes',
              items: [
                ...items.map(([leadingText, trailingText]) => ({ $kind: 'textPair', leadingText, trailingText })),
                { $kind: 'button', action: { title: 'Learn More' } },
              ],
            },
          ],
        },
      },
    ],
  };
  return (
    `<script id=software-application type="application/ld+json">{"@type":"SoftwareApplication",` +
    `"offers":{"@type":"Offer","price":0,"priceCurrency":"${currency}"}}</script>` +
    `<script type="application/json" id="serialized-server-data">${JSON.stringify(data)}</script>`
  );
}

function playPage(currency: string, range: string): string {
  return `<script type="application/ld+json">{"offers":[{"@type":"Offer","price":"0","priceCurrency":"${currency}"}]}</script>
    AF_initDataCallback({data:[null,["0+",0,0,"0+"],null,[2],["${range}",[0]],null]});`;
}

describe('parseAmount', () => {
  it.each([
    ['34,99 €', 'EUR', '34.99'],
    ['$3.99', 'USD', '3.99'],
    ['CHF 25.00', 'CHF', '25.00'],
    ['¥6,800', 'JPY', '6800'],
    ['₩5,500', 'KRW', '5500'],
    ['Rp 59.000', 'IDR', '59000'],
    ['1.234,56 kr', 'DKK', '1234.56'],
    ['1 790,00 Ft', 'HUF', '1790.00'],
    ["CHF 1'234.50", 'CHF', '1234.50'],
    ['₹4,500.00', 'INR', '4500.00'],
    ['KWD 1.990', 'KWD', '1.990'],
    ['٣٫٩٩ ر.س.', 'SAR', '3.99'],
  ])('%s in %s is %s', (text, currency, amount) => {
    expect(parseAmount(text, currency)).toBe(amount);
  });

  it('is null without a number', () => {
    expect(parseAmount('Free', 'USD')).toBeNull();
  });
});

describe('pickMonthlyYearly', () => {
  it('takes the cheaper of two as monthly, in either order', () => {
    expect(
      pickMonthlyYearly([
        { name: 'Velorki Plus jährlich', amount: '34.99' },
        { name: 'Velorki Plus monatlich', amount: '3.99' },
      ]),
    ).toEqual({ monthly: '3.99', yearly: '34.99' });
    expect(pickMonthlyYearly([{ amount: '3.99' }, { amount: '29.99' }])).toEqual({ monthly: '3.99', yearly: '29.99' });
  });

  it('refuses names that contradict the prices', () => {
    expect(() =>
      pickMonthlyYearly([
        { name: 'Velorki Plus Monthly', amount: '34.99' },
        { name: 'Velorki Plus Yearly', amount: '3.99' },
      ]),
    ).toThrow(/disagree/);
  });

  it('needs exactly two different prices', () => {
    expect(pickMonthlyYearly([{ amount: '3.99' }])).toBeNull();
    expect(pickMonthlyYearly([{ amount: '3.99' }, { amount: '3.99' }])).toBeNull();
  });
});

describe('parseAppStorePage', () => {
  it('reads the in-app purchases and the storefront currency', () => {
    const html = appStorePage('EUR', [
      ['Velorki Plus jährlich', '34,99 €'],
      ['Velorki Plus monatlich', '3,99 €'],
    ]);
    expect(parseAppStorePage(html)).toEqual({ currency: 'EUR', monthly: '3.99', yearly: '34.99' });
  });

  it('is null when the storefront lists no purchases', () => {
    expect(parseAppStorePage(appStorePage('JPY', []))).toBeNull();
  });
});

describe('parsePlayPage', () => {
  it('splits the per-item range into monthly and yearly', () => {
    expect(parsePlayPage(playPage('JPY', '¥700 - ¥6,800 per item'))).toEqual({
      currency: 'JPY',
      monthly: '700',
      yearly: '6800',
    });
  });

  it('reads the EEA wording too', () => {
    expect(parsePlayPage(playPage('EUR', '€4.29 - €41.99 if billed through Play'))).toEqual({
      currency: 'EUR',
      monthly: '4.29',
      yearly: '41.99',
    });
  });

  it('is null without a range (the app is not offered there)', () => {
    expect(parsePlayPage(playPage('USD', 'Contains ads'))).toBeNull();
  });
});

describe('store APIs', () => {
  it('turns Google money into a decimal string', () => {
    expect(googleMoney({ units: '34', nanos: 990000000 })).toBe('34.99');
    expect(googleMoney({ units: '700' })).toBe('700');
    expect(googleMoney({ nanos: 500000000 })).toBe('0.5');
  });

  it('joins the Play base plans per region', () => {
    const sub = (basePlanId: string, prices: Record<string, [string, string, number]>) => ({
      basePlans: [
        { basePlanId: 'legacy', regionalConfigs: [{ regionCode: 'US', price: { currencyCode: 'USD', units: '99' } }] },
        {
          basePlanId,
          regionalConfigs: Object.entries(prices).map(([regionCode, [currencyCode, units, nanos]]) => ({
            regionCode,
            price: { currencyCode, units, nanos },
          })),
        },
      ],
    });
    expect(
      playPricesFromSubscriptions(
        sub('monthly', { US: ['USD', '3', 990000000], DE: ['EUR', '4', 290000000], JP: ['JPY', '700', 0] }),
        sub('yearly', { US: ['USD', '34', 990000000], DE: ['EUR', '41', 990000000] }),
      ),
    ).toEqual({
      DE: { currency: 'EUR', monthly: '4.29', yearly: '41.99' },
      US: { currency: 'USD', monthly: '3.99', yearly: '34.99' },
    });
  });

  it('takes the current App Store price per territory, not a scheduled one', () => {
    const price = (id: string, territory: string, point: string, startDate: string | null) => ({
      type: 'subscriptionPrices',
      id,
      attributes: { startDate },
      relationships: {
        territory: { data: { type: 'territories', id: territory } },
        subscriptionPricePoint: { data: { type: 'subscriptionPricePoints', id: point } },
      },
    });
    const pages = [
      {
        data: [price('1', 'DEU', 'p1', null), price('2', 'DEU', 'p2', '2026-12-01'), price('3', 'USA', 'p3', '2026-01-01')],
        included: [
          { type: 'subscriptionPricePoints', id: 'p1', attributes: { customerPrice: '3.99' } },
          { type: 'subscriptionPricePoints', id: 'p2', attributes: { customerPrice: '4.99' } },
          { type: 'subscriptionPricePoints', id: 'p3', attributes: { customerPrice: '3.99' } },
          { type: 'territories', id: 'DEU', attributes: { currency: 'EUR' } },
        ],
      },
      {
        data: [price('4', 'USA', 'p4', '2026-06-01')],
        included: [
          { type: 'subscriptionPricePoints', id: 'p4', attributes: { customerPrice: '4.49' } },
          { type: 'territories', id: 'USA', attributes: { currency: 'USD' } },
        ],
      },
    ];
    const monthly = ascCurrentPrices(pages, '2026-10-23');
    expect(Object.fromEntries(monthly)).toEqual({
      DE: { currency: 'EUR', amount: '3.99' },
      US: { currency: 'USD', amount: '4.49' },
    });
    const yearly = new Map([['DE', { currency: 'EUR', amount: '34.99' }]]);
    expect(joinAsc(monthly, yearly)).toEqual({ DE: { currency: 'EUR', monthly: '3.99', yearly: '34.99' } });
  });
});

describe('defaultCountry', () => {
  it.each([
    ['en', 'US'],
    ['de', 'DE'],
    ['es', 'ES'],
    ['fr', 'FR'],
    ['it', 'IT'],
    ['nl', 'NL'],
    ['pt', 'US'],
  ])('the %s site opens on %s', (locale, country) => {
    expect(defaultCountry(locale)).toBe(country);
  });
});

describe('formatting', () => {
  it('writes money the way the page language does, in the store currency', () => {
    expect(formatPrice('34.99', 'EUR', 'de')).toBe('34,99 €');
    expect(formatPrice('29.99', 'USD', 'en')).toBe('$29.99');
    expect(formatPrice('6800', 'JPY', 'en')).toBe('¥6,800');
  });

  it('dates the table by month', () => {
    expect(formatAsOf('2026-10-23', 'en')).toBe('October 2026');
    expect(formatAsOf('2026-10-01', 'de')).toBe('Oktober 2026');
  });
});

const TABLE: PriceTable = {
  fetchedAt: '2026-10-23',
  source: 'test',
  appStore: {
    DE: { currency: 'EUR', monthly: '3.99', yearly: '34.99' },
    US: { currency: 'USD', monthly: '3.99', yearly: '29.99' },
  },
  googlePlay: {
    DE: { currency: 'EUR', monthly: '4.29', yearly: '41.99' },
    JP: { currency: 'JPY', monthly: '700', yearly: '6800' },
  },
};

const STRINGS = {
  country: 'Country',
  monthly: 'Monthly',
  yearly: 'Yearly',
  asOf: 'As of October 2026',
  tax: 'Tax included',
  missing: 'Shown in the app',
};

describe('PlusPrices', () => {
  it('shows both stores for the page locale’s country before the browser is asked', () => {
    const html = renderToStaticMarkup(<PlusPrices view={priceView(TABLE, 'de')} strings={STRINGS} />);
    expect(html).toContain('3,99 €');
    expect(html).toContain('34,99 €');
    expect(html).toContain('41,99 €');
    expect(html).toContain('App Store');
    expect(html).toContain('Google Play');
    expect(html).toContain('As of October 2026');
    expect(html).not.toContain('Shown in the app');
  });

  it('shows only the store that has a price there', () => {
    const html = renderToStaticMarkup(<PlusPrices view={priceView(TABLE, 'en')} strings={STRINGS} />);
    expect(html).toContain('$29.99');
    expect(html).not.toContain('Google Play');
  });

  it('falls back to the app when neither store has a price', () => {
    const html = renderToStaticMarkup(<PlusPrices view={priceView(TABLE, 'fr')} strings={STRINGS} />);
    expect(html).toContain('Shown in the app');
    // France is still offered in the list, so the reader can see what was picked.
    expect(html).toMatch(/<option value="FR" selected="">/);
  });
});

describe('the committed table', () => {
  it('has prices for the main countries in both stores', () => {
    expect(PRICES.fetchedAt).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    for (const store of ['appStore', 'googlePlay'] as const) {
      for (const cc of ['DE', 'US', 'GB']) {
        const price = PRICES[store][cc];
        expect(price, `${store} ${cc}`).toBeDefined();
        expect(Number(price!.monthly)).toBeLessThan(Number(price!.yearly));
      }
    }
    expect(pricedCountries(PRICES).length).toBeGreaterThan(30);
  });

  it('quotes example countries in llms.txt', () => {
    const lines = priceLines(TABLE).join('\n');
    expect(lines).toContain('https://');
    expect(lines).toContain('Germany: App Store €3.99 a month or €34.99 a year; Google Play €4.29 a month or €41.99 a year.');
    expect(lines).toContain('United States: App Store $3.99 a month or $29.99 a year.');
  });
});
