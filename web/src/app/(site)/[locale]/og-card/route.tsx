// SPDX-License-Identifier: AGPL-3.0-only
// The share card, generated at build time with next/og. Deliberately typeset in
// the default font: pulling the app's TTFs in would add a runtime file read for
// a picture, and the card is a colour field with three lines of text.
//
// A plain route handler, not Next's `opengraph-image.tsx` convention: that one
// mints a URL with a build hash in it (`/en/opengraph-image-<hash>`) that
// nothing outside Next can predict, and it is always locale-prefixed. With
// `localePrefix: 'as-needed'` the English prefix is stripped again by
// next-intl, so the tag pointed at a 307 and a crawler that does not follow
// redirects got no card. Here the path is ours: `/og-card` and `/de/og-card`,
// both a direct 200. `src/site/seo.ts` writes the tags.
import { getTranslations } from 'next-intl/server';
import { ogCardImage } from '@/components/OgCard';
import { routing } from '@/i18n/routing';

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function GET(
  _request: Request,
  ctx: { params: Promise<{ locale: string }> },
): Promise<Response> {
  const { locale } = await ctx.params;
  const t = await getTranslations({ locale, namespace: 'site' });
  return ogCardImage(t('tagline'));
}
