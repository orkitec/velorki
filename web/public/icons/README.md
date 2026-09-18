# Site icons

Everything here is generated from `app/assets/icon/` — nothing is drawn by
hand. The source of truth for the shape is `app/assets/icon/icon.svg` and
`icon_foreground.svg`; `web/public/icon.svg` and
`web/src/components/AppIcon.tsx` are two renderings of the same composition and
have to be changed together.

## What the composition is

A launcher never shows the raw artwork. Android draws the adaptive icon —
background `#1B7F5A` plus `icon_foreground.svg` inset a further 16 % by
`app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` — on a 108 dp
canvas and then masks it down to the inner 72 dp. The mask throws away a third
of the canvas, so whatever survives is magnified by 108 / 72 = 1.5:

```
0.9 (icon_foreground.svg) × 0.68 (16 % inset) × 1.5 (mask) = 0.918
```

So the glyph fills 57.4 % of the tile it is drawn on, and the corners are
rounded by about 22 %. Dropping the flat `icon.svg` into a favicon instead —
which is what the site did before — gives square corners and a glyph at 62.5 %,
and using the bare route glyph with no tile at all, as the header used to,
looks like a different logo.

## Regenerating

Needs `rsvg-convert` (librsvg) and ImageMagick; neither is an npm dependency,
and nothing in the build calls them. Run from `web/`:

```sh
ICON=public/icon.svg; APP=../app/assets/icon
gen() {                     # $1 source svg, $2 size, $3 output
  rsvg-convert -w $(( $2 * 4 )) -h $(( $2 * 4 )) "$1" -o /tmp/icon-big.png
  magick /tmp/icon-big.png -filter Lanczos -resize "$2x$2" -strip "$3"
}
gen $ICON 32  public/icons/favicon-32.png
gen $ICON 192 public/icons/icon-192.png
gen $ICON 512 public/icons/icon-512.png

# apple-touch-icon: iOS applies its own squircle, so this one is the flat
# full-bleed square, i.e. exactly the iOS AppIcon artwork.
rsvg-convert -w 720 -h 720 $APP/icon.svg -o /tmp/at.png
magick /tmp/at.png -filter Lanczos -resize 180x180 -alpha remove -alpha off \
  -strip public/icons/apple-touch-icon.png

# maskable: the adaptive icon before the mask — background plus the foreground
# inset 16 %, full bleed, so a launcher can crop it to any shape.
rsvg-convert -w 1392 -h 1392 $APP/icon_foreground.svg -o /tmp/fg.png
magick -size 2048x2048 xc:'#1B7F5A' /tmp/fg.png -geometry +328+328 -composite \
  -filter Lanczos -resize 512x512 -alpha remove -alpha off -strip \
  public/icons/icon-512-maskable.png

# favicon.ico: 16, 32 and 48 in one file.
for n in 16 32 48; do
  rsvg-convert -w $((n*4)) -h $((n*4)) $ICON -o /tmp/f$n.big.png
  magick /tmp/f$n.big.png -filter Lanczos -resize ${n}x${n} /tmp/f$n.png
done
magick /tmp/f16.png /tmp/f32.png /tmp/f48.png public/favicon.ico
```

`public/icon.svg` itself is the 1024 tile with `rx = 225.28` (22 %) and the
glyph coordinates of `icon.svg` scaled by 0.918 about (512, 512).
`AppIcon.tsx` computes those same numbers at render time.
