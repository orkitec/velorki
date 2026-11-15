// SPDX-License-Identifier: AGPL-3.0-only
// The share card's drawing, apart from its route so a blog post can have the
// same card with its own title in the place of the tagline
// (src/app/(site)/[locale]/blog/[slug]/og-card/route.tsx). Deliberately
// typeset in the default font: see src/app/(site)/[locale]/og-card/route.tsx.
import { ImageResponse } from 'next/og';
import { AppIcon, ICON_GLYPH_DARK, ICON_TILE_DARK } from '@/components/AppIcon';
import { OG_IMAGE_SIZE } from '@/site/seo';

/** The card with `text` as its big line: the tagline, or a post's title. */
export function ogCardImage(text: string): ImageResponse {
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
          {/* satori draws no CSS custom properties, and the card is dark. */}
          <AppIcon size={72} tile={ICON_TILE_DARK} glyph={ICON_GLYPH_DARK} />
          <div style={{ fontSize: 56, fontWeight: 700, letterSpacing: -1 }}>Velorki</div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
          <div style={{ fontSize: 44, lineHeight: 1.2, maxWidth: 960 }}>{text}</div>
          <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap' }}>
            {['Private', 'No account', 'Offline', 'Open source'].map((chip) => (
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
