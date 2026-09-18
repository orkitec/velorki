// SPDX-License-Identifier: AGPL-3.0-only
// The app icon as the launcher draws it, in one place: the site header, the
// footer, the favicons and the share card all come from here, so the logo on
// the web cannot drift away from the one on the phone. The colours come from
// `AppIcon.css`, so the icon is the light one on a light page and the dark
// (neon) one on a dark page; a caller that satori or a rasteriser draws — the
// share card, the generated PNGs — passes `tile` and `glyph` instead.
//
// Why the glyph is scaled: `app/assets/icon/icon_foreground.svg` draws the
// route mark at 90 % of its 1024 canvas, and Android's adaptive icon
// (`app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`) insets
// that foreground by a further 16 % per side before masking the 108 dp canvas
// down to the inner 72 dp. The mask throws away a third of the canvas, so
// whatever survives is magnified by 108/72 = 1.5 relative to the tile:
//
//   0.9 (foreground svg) × 0.68 (16 % inset) × 1.5 (mask) = 0.918
//
// Drawing the raw foreground into a tile — which is what the site used to do —
// makes the mark 1.5× too small and the wrong shape. See assets/icon/README.md.
import type { SVGProps } from 'react';
import './AppIcon.css';

/** The light icon: the volt accent's light tone (`AccentPreset.volt.light`). */
export const ICON_TILE_LIGHT = '#3F7A00';
/** The glyph on the light icon. */
export const ICON_GLYPH_LIGHT = '#FFFFFF';
/** The dark icon: the volt accent itself (`AccentPreset.volt.dark`). */
export const ICON_TILE_DARK = '#C8F542';
/** The glyph on the dark icon: the app's ink. */
export const ICON_GLYPH_DARK = '#0E1115';

// Themed by `AppIcon.css`; the fallback is the dark icon, which is what
// everything that cannot read CSS gets.
const TILE = `var(--app-icon-tile, ${ICON_TILE_DARK})`;
const GLYPH = `var(--app-icon-glyph, ${ICON_GLYPH_DARK})`;

/** 0.9 × 0.68 × 1.5 — see the note above. */
const GLYPH_SCALE = 0.918;
/** Android's and iOS' corner masks are both close to 22 % of the tile. */
const CORNER_RADIUS = 0.22 * 1024;

/** A coordinate of `icon.svg`, scaled about the centre of the 1024 canvas. */
function s(v: number): number {
  return Number((512 + (v - 512) * GLYPH_SCALE).toFixed(2));
}

// The glyph, in the coordinates of assets/icon/icon.svg: three waypoint rings
// — a start, a via point and a finish — joined by two gently bowed route
// strokes that read as a V. Pre-scaled here rather than wrapped in a
// `transform`, because `next/og` (satori) draws the flat attributes and
// ignores a group transform.
const ROUTE =
  `M${s(296)} ${s(308)} Q ${s(337)} ${s(545)} ${s(512)} ${s(716)}` +
  ` Q ${s(687)} ${s(545)} ${s(728)} ${s(308)}`;
const STROKE = Number((72 * GLYPH_SCALE).toFixed(2));
const RING = Number((104 * GLYPH_SCALE).toFixed(2));
const HOLE = Number((44 * GLYPH_SCALE).toFixed(2));
const WAYPOINTS = [
  { cx: s(296), cy: s(308) },
  { cx: s(728), cy: s(308) },
  { cx: s(512), cy: s(716) },
];

export interface AppIconProps extends Omit<SVGProps<SVGSVGElement>, 'width' | 'height'> {
  /** Edge length in pixels; the icon is always square. */
  size?: number;
  /** The tile, when the caller cannot use the themed custom property. */
  tile?: string;
  /** The glyph, likewise. */
  glyph?: string;
}

/**
 * The Velorki app icon: the tile with the route glyph, at the size and corner
 * rounding a launcher gives it. Light or dark with the page, unless the caller
 * names the two colours.
 */
export function AppIcon({ size = 32, tile = TILE, glyph = GLYPH, ...props }: AppIconProps) {
  return (
    <svg
      viewBox="0 0 1024 1024"
      width={size}
      height={size}
      aria-hidden="true"
      focusable="false"
      {...props}
    >
      <rect width="1024" height="1024" rx={CORNER_RADIUS} ry={CORNER_RADIUS} fill={tile} />
      <path
        d={ROUTE}
        fill="none"
        stroke={glyph}
        strokeWidth={STROKE}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {WAYPOINTS.map((p) => (
        <circle key={`${p.cx},${p.cy}`} cx={p.cx} cy={p.cy} r={RING} fill={glyph} />
      ))}
      {WAYPOINTS.map((p) => (
        <circle key={`hole-${p.cx},${p.cy}`} cx={p.cx} cy={p.cy} r={HOLE} fill={tile} />
      ))}
    </svg>
  );
}
