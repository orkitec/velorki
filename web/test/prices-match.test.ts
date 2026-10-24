// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import {
  checkLimits,
  decimalToNanos,
  formatMoney,
  markdownTable,
  matchPlayToApple,
  summarise,
  toGoogleMoney,
  withTargets,
} from '../scripts/prices-match.mjs';

type Money = { currencyCode: string; units: string; nanos?: number };

const money = (currencyCode: string, units: string, nanos = 0): Money => ({ currencyCode, units, nanos });

/** A monetization.subscriptions.get answer with one base plan. */
function subscription(productId: string, basePlanId: string, regions: Record<string, Money>) {
  return {
    packageName: 'com.orkitec.velorki',
    productId,
    listings: [{ languageCode: 'en-US', title: 'Velorki Plus' }],
    basePlans: [
      {
        basePlanId,
        state: 'ACTIVE',
        autoRenewingBasePlanType: { billingPeriodDuration: basePlanId === 'monthly' ? 'P1M' : 'P1Y' },
        regionalConfigs: Object.entries(regions).map(([regionCode, price]) => ({
          regionCode,
          newSubscriberAvailability: true,
          price,
        })),
        otherRegionsConfig: { usdPrice: money('USD', '3', 990000000), eurPrice: money('EUR', '3', 990000000) },
      },
    ],
  };
}

const PLAY = {
  monthly: subscription('plus_monthly', 'monthly', {
    DE: money('EUR', '4', 290000000),
    US: money('USD', '3', 990000000),
    RS: money('RSD', '499'),
    JP: money('JPY', '700'),
    BR: money('BRL', '20', 990000000),
  }),
  yearly: subscription('plus_yearly', 'yearly', {
    DE: money('EUR', '41', 990000000),
    US: money('USD', '34', 990000000),
    RS: money('RSD', '4899'),
    JP: money('JPY', '6800'),
    BR: money('BRL', '204', 990000000),
  }),
};

const APPLE = {
  DE: { currency: 'EUR', monthly: '3.99', yearly: '34.99' },
  US: { currency: 'USD', monthly: '3.99', yearly: '29.99' },
  RS: { currency: 'EUR', monthly: '3.99', yearly: '34.99' },
  JP: { currency: 'JPY', monthly: '600', yearly: '5000' },
};

const row = (rows: ReturnType<typeof matchPlayToApple>, region: string, period: string) =>
  rows.find((r) => r.region === region && r.period === period);

describe('money conversion', () => {
  it('turns a decimal amount into units and nanos', () => {
    expect(toGoogleMoney('EUR', '3.99')).toEqual({ currencyCode: 'EUR', units: '3', nanos: 990000000 });
    expect(toGoogleMoney('EUR', '34.99')).toEqual({ currencyCode: 'EUR', units: '34', nanos: 990000000 });
    expect(toGoogleMoney('CHF', '25.00')).toEqual({ currencyCode: 'CHF', units: '25', nanos: 0 });
    expect(toGoogleMoney('JPY', '6800')).toEqual({ currencyCode: 'JPY', units: '6800', nanos: 0 });
    expect(toGoogleMoney('KWD', '1.234')).toEqual({ currencyCode: 'KWD', units: '1', nanos: 234000000 });
  });

  it("rounds half up to the currency's minor unit", () => {
    expect(toGoogleMoney('EUR', '3.995')).toEqual({ currencyCode: 'EUR', units: '4', nanos: 0 });
    expect(toGoogleMoney('EUR', '3.994')).toEqual({ currencyCode: 'EUR', units: '3', nanos: 990000000 });
    expect(toGoogleMoney('JPY', '499.5')).toEqual({ currencyCode: 'JPY', units: '500', nanos: 0 });
    expect(toGoogleMoney('USD', '0.1')).toEqual({ currencyCode: 'USD', units: '0', nanos: 100000000 });
  });

  it('refuses what is not a number, without floats', () => {
    expect(toGoogleMoney('EUR', '3,99')).toBeNull();
    expect(toGoogleMoney('EUR', '')).toBeNull();
    expect(decimalToNanos('0.29')).toBe(290000000n);
    expect(decimalToNanos('1000000.01')).toBe(1000000010000000n);
  });

  it("formats in the currency's own digits", () => {
    expect(formatMoney(money('EUR', '4', 290000000))).toBe('4.29');
    expect(formatMoney(money('CHF', '33'))).toBe('33.00');
    expect(formatMoney(money('JPY', '700'))).toBe('700');
    expect(formatMoney(money('USD', '0', 50000000))).toBe('0.05');
  });
});

describe('matchPlayToApple', () => {
  const rows = matchPlayToApple(PLAY, APPLE);

  it("gives a region Apple's price where the currency is the same", () => {
    expect(row(rows, 'DE', 'monthly')).toMatchObject({ status: 'update', target: toGoogleMoney('EUR', '3.99') });
    expect(row(rows, 'DE', 'yearly')).toMatchObject({ status: 'update', target: toGoogleMoney('EUR', '34.99') });
    expect(row(rows, 'JP', 'yearly')).toMatchObject({ status: 'update', target: toGoogleMoney('JPY', '5000') });
    expect(row(rows, 'US', 'yearly')).toMatchObject({ status: 'update', target: toGoogleMoney('USD', '29.99') });
  });

  it('leaves a price that is already Apple’s', () => {
    expect(row(rows, 'US', 'monthly')?.status).toBe('same');
  });

  it('leaves a region in another currency than Apple’s', () => {
    expect(row(rows, 'RS', 'monthly')).toMatchObject({ status: 'currency', target: null });
    expect(row(rows, 'RS', 'monthly')?.note).toContain('EUR 3.99');
  });

  it('leaves a region where Apple has no price', () => {
    expect(row(rows, 'BR', 'monthly')).toMatchObject({ status: 'missing', target: null });
  });

  it('counts every row once', () => {
    expect(summarise(rows)).toEqual({ update: 5, same: 1, currency: 2, missing: 2, blocked: 0 });
    expect(rows).toHaveLength(10);
  });

  it('throws when a base plan is not there', () => {
    expect(() => matchPlayToApple({ monthly: PLAY.monthly, yearly: subscription('plus_yearly', 'annual', {}) }, APPLE)).toThrow(
      /no base plan yearly/,
    );
  });
});

describe('checkLimits', () => {
  it('blocks a target above the ceiling', () => {
    const rows = checkLimits(matchPlayToApple(PLAY, APPLE), { DE: decimalToNanos('30') });
    expect(row(rows, 'DE', 'yearly')).toMatchObject({ status: 'blocked' });
    expect(row(rows, 'DE', 'yearly')?.note).toContain('ceiling');
    expect(row(rows, 'DE', 'monthly')?.status).toBe('update');
  });

  it('blocks a target more than twice or under half the current price', () => {
    const rows = checkLimits(
      matchPlayToApple(PLAY, { ...APPLE, DE: { currency: 'EUR', monthly: '0.39', yearly: '349.99' } }),
    );
    expect(row(rows, 'DE', 'monthly')?.status).toBe('blocked');
    expect(row(rows, 'DE', 'yearly')?.status).toBe('blocked');
  });

  it('passes the ordinary differences', () => {
    expect(summarise(checkLimits(matchPlayToApple(PLAY, APPLE))).blocked).toBe(0);
  });
});

describe('withTargets', () => {
  it('replaces only the updated prices and keeps the rest of the subscription', () => {
    const rows = matchPlayToApple(PLAY, APPLE);
    const patched = withTargets(PLAY.yearly, 'yearly', rows);
    const prices = Object.fromEntries(patched.basePlans[0]!.regionalConfigs.map((c) => [c.regionCode, c.price]));
    expect(prices).toEqual({
      DE: toGoogleMoney('EUR', '34.99'),
      US: toGoogleMoney('USD', '29.99'),
      RS: money('RSD', '4899'),
      JP: toGoogleMoney('JPY', '5000'),
      BR: money('BRL', '204', 990000000),
    });
    expect(patched.basePlans[0]!.otherRegionsConfig).toEqual(PLAY.yearly.basePlans[0]!.otherRegionsConfig);
    expect(patched.listings).toEqual(PLAY.yearly.listings);
    // The original is untouched.
    expect(PLAY.yearly.basePlans[0]!.regionalConfigs[0]!.price).toEqual(money('EUR', '41', 990000000));
  });

  it('leaves a blocked row out', () => {
    const rows = checkLimits(matchPlayToApple(PLAY, APPLE), { DE: decimalToNanos('30') });
    const patched = withTargets(PLAY.yearly, 'yearly', rows);
    expect(patched.basePlans[0]!.regionalConfigs.find((c) => c.regionCode === 'DE')?.price).toEqual(
      money('EUR', '41', 990000000),
    );
  });
});

describe('markdownTable', () => {
  it('shows current → target per region and base plan', () => {
    const table = markdownTable(matchPlayToApple(PLAY, APPLE));
    expect(table).toContain("| DE | EUR | plus_yearly:yearly | 41.99 | 34.99 | → App Store's price |");
    expect(table).toContain("| US | USD | plus_monthly:monthly | 3.99 |  | already the App Store's price |");
    expect(table).toContain('| RS | RSD | plus_monthly:monthly | 499.00 |  | App Store charges EUR 3.99 here |');
  });
});
