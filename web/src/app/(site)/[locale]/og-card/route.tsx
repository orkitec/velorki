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
import { ImageResponse } from 'next/og';
import { getTranslations } from 'next-intl/server';
import { routing } from '@/i18n/routing';
import { OG_IMAGE_SIZE } from '@/site/seo';

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function GET(
  _request: Request,
  ctx: { params: Promise<{ locale: string }> },
): Promise<Response> {
  const { locale } = await ctx.params;
  const t = await getTranslations({ locale, namespace: 'site' });

  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'space-between',
          background: '#0E1115',
          padding: '72px 80px',
          color: '#F1F3F5',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 20 }}>
          <svg width="64" height="64" viewBox="0 0 1024 1024">
            <path d="M296 716 Q 360 400 728 308" fill="none" stroke="#C8F542" strokeWidth="96" strokeLinecap="round" />
            <circle cx="296" cy="716" r="118" fill="#C8F542" />
            <circle cx="728" cy="308" r="118" fill="#C8F542" />
          </svg>
          <div style={{ fontSize: 56, fontWeight: 700, letterSpacing: -1 }}>Velorki</div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
          <div style={{ fontSize: 44, lineHeight: 1.2, maxWidth: 960 }}>{t('tagline')}</div>
          <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap' }}>
            {['Offline', 'OpenStreetMap', 'Open source', 'No account'].map((chip) => (
              <div
                key={chip}
                style={{
                  display: 'flex',
                  border: '2px solid #2C333C',
                  borderRadius: 999,
                  padding: '8px 22px',
                  fontSize: 24,
                  color: '#AAB2BC',
                }}
              >
                {chip}
              </div>
            ))}
          </div>
        </div>

        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 26, color: '#C8F542' }}>
          <div style={{ display: 'flex' }}>velorki.com</div>
          <div style={{ display: 'flex', color: '#AAB2BC' }}>Android · iOS</div>
        </div>
      </div>
    ),
    { ...OG_IMAGE_SIZE, headers: { 'cache-control': 'public, max-age=86400' } },
  );
}
