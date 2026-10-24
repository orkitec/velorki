// SPDX-License-Identifier: AGPL-3.0-only
'use client';

import { useId, useState } from 'react';
import { AppleIcon, ChevronDownIcon, GooglePlayIcon } from '@/components/Icons';
import { STORES, type PriceView, type Store } from '@/site/prices';

export interface PlusPricesStrings {
  country: string;
  monthly: string;
  yearly: string;
  /** "As of October 2026", already formatted on the server. */
  asOf: string;
  tax: string;
  /** For a country neither store has a price for. */
  missing: string;
}

/** The stores' own names, the same in every language. */
const STORE_NAMES: Record<Store, string> = { appStore: 'App Store', googlePlay: 'Google Play' };

/**
 * The monthly and yearly Plus price in one country, App Store and Google Play
 * side by side. The list opens on the page language's country and can be
 * changed; nothing is sent anywhere, the table is in the page.
 */
export function PlusPrices({ view, strings }: { view: PriceView; strings: PlusPricesStrings }) {
  const selectId = useId();
  const [country, setCountry] = useState(view.initial);
  const shown = view.prices[country] ?? {};
  const offered = STORES.filter((store) => shown[store] !== undefined);

  return (
    <div className="panel mt-6 p-6">
      <label htmlFor={selectId} className="flex flex-wrap items-center gap-3 font-bold">
        {strings.country}
        <span className="relative">
          <select
            id={selectId}
            value={country}
            onChange={(event) => setCountry(event.target.value)}
            className="appearance-none rounded-full border border-line bg-panel-2 py-2 pl-4 pr-10 font-normal text-fg hover:border-accent focus-visible:border-accent"
          >
            {view.countries.map(({ code, name }) => (
              <option key={code} value={code}>
                {name}
              </option>
            ))}
          </select>
          <ChevronDownIcon
            width={16}
            height={16}
            aria-hidden
            className="pointer-events-none absolute right-4 top-1/2 -translate-y-1/2 text-muted"
          />
        </span>
      </label>

      {offered.length === 0 ? (
        <p className="mt-5 text-muted">{strings.missing}</p>
      ) : (
        <ul className="mt-6 grid gap-6 sm:grid-cols-2">
          {offered.map((store) => (
            <StoreColumn key={store} store={store} price={shown[store]!} strings={strings} />
          ))}
        </ul>
      )}

      <p className="mt-6 text-sm text-muted">
        {strings.asOf} · {strings.tax}
      </p>
    </div>
  );
}

function StoreColumn({
  store,
  price,
  strings,
}: {
  store: Store;
  price: { monthly: string; yearly: string };
  strings: PlusPricesStrings;
}) {
  const Icon = store === 'appStore' ? AppleIcon : GooglePlayIcon;
  return (
    <li>
      <h3 className="flex items-center gap-2 font-display text-xl">
        <Icon width={20} height={20} />
        {STORE_NAMES[store]}
      </h3>
      <dl className="mt-3 grid grid-cols-[auto_1fr] gap-x-6 gap-y-1 text-lg">
        <dt className="text-muted">{strings.monthly}</dt>
        <dd className="font-bold tabular-nums">{price.monthly}</dd>
        <dt className="text-muted">{strings.yearly}</dt>
        <dd className="font-bold tabular-nums">{price.yearly}</dd>
      </dl>
    </li>
  );
}
