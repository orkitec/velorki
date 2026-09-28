# Store assets

The App Store listing is built from the repository: the texts are fastlane
metadata, the screenshots are taken from the real app and turned into slides
by a script. Nothing is drawn by hand, so a new language or a changed screen
is a rerun.

## Texts

`app/fastlane/metadata/ios/<locale>/` (name, subtitle, keywords, description,
promotional text) and `app/fastlane/metadata/android/<locale>/`. English is
edited here, other languages come from Crowdin, and `app/tool/store_text_check.py`
holds every file to its store's length limit. See [LOCALISATION.md](LOCALISATION.md).

## Screenshots

```
app/tool/store_screenshots.sh [--locales en,de] [--themes light,dark] [--shots same|light|dark] [--skip-capture]
```

1. **Capture.** On the iOS simulator "Velorki Shots 6.9" (an iPhone 17 Pro
   Max, created on the first run), once per language: the simulator's
   language and region are set, the status bar reads 9:41 with full bars,
   and `app/integration_test/store/store_screenshots_test.dart` takes six
   screens in each theme — the plan with its elevation profile, the route
   variants, navigation with the turn banner and the figures bar, a ride's
   charts, the library and a GPX import. Everything is on Madeira and
   computed on the device from the tile `app/tool/itest_mirror.sh` serves;
   the ride is laid along a route the device plans, with a speed from the
   gradient and a heart rate from the effort. The test clears that
   simulator's library first. It is not part of the integration suite.
2. **Slides.** `app/tool/store_slides.py` puts each screenshot in a phone
   frame under a headline and a subline, with headless Chrome and the app's
   own fonts. Two styles: `dark` (deep green, lime) and `light` (pale lime,
   deep green). Each style shows the app in the matching theme unless
   `--shots` says otherwise. A headline too long for three lines shrinks to
   fit.

Output, git-ignored:

- `app/build/store_screenshots/raw/<theme>/<locale>/NN-name.png`, 1320 × 2868
- `app/build/store_screenshots/slides/<style>/<size>/<locale>/NN-name.png`

The copy is `app/store/slides_en.json`: per slide a `headline` with the
emphasised word in `**`, a `subline` and an optional `badge`. Other languages
are `slides_<lang>.json`, from Crowdin; a slide missing there falls back to
English.

## Adding a language

1. The app strings, the store texts and `slides_<lang>.json` arrive through
   Crowdin.
2. If the store's region for the language is not in `region_of` in
   `store_screenshots.sh`, add it.
3. `app/tool/store_screenshots.sh --locales <lang>`.

## Uploading

In App Store Connect, the version's page, per localization:

| Folder | Field |
|---|---|
| `slides/<style>/6.9/<locale>/` | iPhone 6.9" Display |
| `slides/<style>/6.5/<locale>/` | iPhone 6.5" Display |

Upload them in file order. A localization without its own screenshots shows
the primary language's.

The App Store shows one set of screenshots whatever the viewer's appearance,
so the listing uses one style. Product Page Optimization (App Store Connect →
the app → Product Page Optimization) runs the other style as a treatment
against it, to see which converts better.
