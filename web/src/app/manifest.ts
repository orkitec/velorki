// SPDX-License-Identifier: AGPL-3.0-only
import type { MetadataRoute } from 'next';

/**
 * The web app manifest. The site is not an installable app — this is here so
 * the browser has a name, a colour and an icon for a bookmark or a pinned tab.
 * The icons are the app icon as a launcher draws it — the rounded tile of
 * `public/icon.svg`, mirrored by `src/components/AppIcon.tsx`. The maskable
 * one is the adaptive icon before the mask (full bleed, glyph inset), so a
 * launcher that crops it to its own shape lands on the same picture as the
 * installed app. See `public/icons/README.md`.
 */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'Velorki — bike route planner',
    short_name: 'Velorki',
    description:
      'Plan bike routes, generate loops and record rides — offline, on OpenStreetMap data. Free and open source.',
    start_url: '/',
    scope: '/',
    display: 'browser',
    background_color: '#0e1115',
    theme_color: '#0e1115',
    categories: ['navigation', 'sports', 'travel'],
    icons: [
      { src: '/icon.svg', type: 'image/svg+xml', sizes: 'any', purpose: 'any' },
      { src: '/icons/icon-192.png', type: 'image/png', sizes: '192x192' },
      { src: '/icons/icon-512.png', type: 'image/png', sizes: '512x512' },
      { src: '/icons/icon-512-maskable.png', type: 'image/png', sizes: '512x512', purpose: 'maskable' },
      { src: '/icons/apple-touch-icon.png', type: 'image/png', sizes: '180x180' },
    ],
  };
}
