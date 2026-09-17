// SPDX-License-Identifier: AGPL-3.0-only
import { getRequestConfig } from 'next-intl/server';
import { hasLocale } from 'next-intl';
import { routing } from './routing';

type Catalogue = Record<string, unknown>;

function isNamespace(value: unknown): value is Catalogue {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * English under the locale's own strings, key by key.
 *
 * A shallow spread would replace a whole namespace with the locale's version,
 * so one key missing inside `docs` would throw at render rather than fall back.
 * `npm run locales -- --check` fails CI on a catalogue whose keys differ from
 * English at all; this is what keeps a page rendering in the meantime.
 */
function mergeCatalogues(base: Catalogue, own: Catalogue): Catalogue {
  const merged: Catalogue = { ...base };
  for (const [key, value] of Object.entries(own)) {
    const current = merged[key];
    merged[key] = isNamespace(current) && isNamespace(value) ? mergeCatalogues(current, value) : value;
  }
  return merged;
}

export default getRequestConfig(async ({ requestLocale }) => {
  const requested = await requestLocale;
  const locale = hasLocale(routing.locales, requested) ? requested : routing.defaultLocale;
  type Module = { default: Catalogue };
  const base = (await import(`../../messages/en.json`)) as Module;
  const own = (await import(`../../messages/${locale}.json`)) as Module;
  return { locale, messages: mergeCatalogues(base.default, own.default) };
});
