# App icon

`icon.svg` is the source. Everything else is generated from it.

The mark is a rounded square in the app's seed colour — `velorkiSeedColor`,
`#1B7F5A`, from `lib/app/theme.dart` — with a white route glyph: two waypoint
circles joined by a curved line. No text, and no reference to any partner
brand (Strava's guidelines forbid their name in an app icon).

## Regenerating

```sh
cd app/assets/icon
rsvg-convert -w 1024 -h 1024 icon.svg            -o icon.png
rsvg-convert -w 1024 -h 1024 icon_foreground.svg -o icon_foreground.png
cd ../.. && dart run flutter_launcher_icons
```

Any SVG rasteriser does; `magick -background none icon.svg -resize 1024x1024
icon.png` or Pillow produce the same thing. `flutter_launcher_icons` is
configured in `pubspec.yaml` and writes:

* `android/app/src/main/res/mipmap-*/ic_launcher.png` (legacy launcher icon),
* `android/app/src/main/res/drawable-*/ic_launcher_foreground.png` plus
  `mipmap-anydpi-v26/ic_launcher.xml` and the `ic_launcher_background` colour
  in `values/colors.xml` (the adaptive icon),
* `ios/Runner/Assets.xcassets/AppIcon.appiconset/*` with the alpha channel
  removed, which the App Store requires.

`icon_foreground.svg` scales the glyph to 90 % because the generated
`ic_launcher.xml` insets the foreground by a further 16 %; together that keeps
the mark inside the adaptive icon's safe zone on every mask shape.

## Store listings

Both stores want the same square artwork as a separate upload — the icon in
the app bundle is not reused:

* Google Play → Store listing → App icon: **512 × 512** PNG, 32-bit, no
  transparency. `rsvg-convert -w 512 -h 512 icon.svg -o velorki-play-512.png`.
* App Store Connect → App information → App icon: **1024 × 1024** PNG, no
  transparency, no rounded corners of your own (`icon.png` as it is).

Generate them when the listing is filled in; they are not committed because
nothing in the build uses them.
