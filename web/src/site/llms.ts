// SPDX-License-Identifier: AGPL-3.0-only
// Paragraphs llms.txt and llms-full.txt share. English only, like both files.
import { PLANNER_URL } from './config';
import { localeUrl } from './paths';
import { PRICES, formatAsOf, formatPrice, type PriceTable } from './prices';

/**
 * Cloud sync, from app/lib/features/sync: one cloud per device, chosen in
 * Settings → Sync with; iCloud through CloudKit (iOS) or CloudKit JS (the
 * browser), Google Drive's hidden app folder everywhere.
 */
export const SYNC_LINES = [
  'Sync between your own devices is free and goes through your own cloud: each device picks iCloud,',
  'Google Drive or Off under Settings → Sync with. iCloud works on iPhone and iPad (iOS 17 or later,',
  'on by default there) and in the browser planner; Google Drive on iPhone, iPad, Android and the',
  'browser, in a hidden app folder (Velorki can see nothing else in the Drive). Routes, rides (track,',
  'notes, figures, laps, sensor readings) and a few settings sync; Strava data does not. Velorki runs',
  'no server for it and cannot read what is stored.',
];

/**
 * The web planner, from what the browser build offers (`PlatformFeatures.browser`
 * in app/lib/app/platform_features.dart, and app/lib/features/sync for the
 * cloud and Plus). Empty where no planner is deployed (PLANNER_URL).
 */
export function plannerLines(): string[] {
  if (!PLANNER_URL) return [];
  return [
    `The planner also runs in a web browser at ${PLANNER_URL}: the same app, free, nothing to install,`,
    'no account. It computes routes in the browser with the same routing as the phone, plans loops,',
    'shows the elevation profile, place search, the cycle map, stops and the weather map, and keeps a',
    'library that syncs with your own iCloud or Google Drive. Velorki Plus cannot be bought there; it',
    'works in the browser once an app with Plus syncs to the same iCloud or Google account. The',
    'browser does not record rides or navigate, keeps no offline map areas, and does not connect',
    'Strava or Ride with GPS: those stay in the app.',
  ];
}

/** The countries quoted as examples; every other one is on the Plus page. */
const PRICE_EXAMPLES = ['US', 'GB', 'DE'];

/**
 * What Plus costs, from src/site/prices.json: where the full table is, and the
 * example countries' prices in both stores.
 */
export function priceLines(table: PriceTable = PRICES): string[] {
  const examples = PRICE_EXAMPLES.flatMap((cc) => {
    const stores = (
      [
        ['App Store', table.appStore[cc]],
        ['Google Play', table.googlePlay[cc]],
      ] as const
    ).flatMap(([store, price]) =>
      price
        ? [
            `${store} ${formatPrice(price.monthly, price.currency, 'en')} a month or ` +
              `${formatPrice(price.yearly, price.currency, 'en')} a year`,
          ]
        : [],
    );
    if (stores.length === 0) return [];
    const name = new Intl.DisplayNames(['en'], { type: 'region' }).of(cc) ?? cc;
    return [`${name}: ${stores.join('; ')}.`];
  });
  return [
    'Plus is monthly or yearly through the App Store or Google Play, with a free trial. The price in',
    'each country, as the stores show it (with tax where the store includes it), is on',
    localeUrl('en', '/plus') +
      (examples.length > 0 ? `; as of ${formatAsOf(table.fetchedAt, 'en')}:` : '.'),
    ...examples.map((line) => `- ${line}`),
  ];
}
