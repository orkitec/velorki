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
   language and region are set, the status bar reads 9:41, and
   `app/integration_test/store/store_screenshots_test.dart` takes every screen
   the slides use, in each theme: the plan (in the dark theme also in another
   accent), its variants, a loop, a GPX import, a ride's charts, the library, a
   route under a status bar with no signal, and a ride under way, once with
   the live card and once navigating with the figures bar. Everything is on
   Madeira and computed on the device from the tile `app/tool/itest_mirror.sh`
   serves. The demo ride is laid along a route the device plans, with a speed
   from the gradient and a heart rate from the effort; the ride under way is
   the same model, fed to the real recorder with its clock and a heart-rate
   sensor following the fixes, so about 20 km and an hour in take a minute.
   The test also saves the figures the Live Activity shows at the moment of
   the live card. It clears that simulator's library first and is not part of
   the integration suite.
2. **Watch.** `app/tool/store_watch.sh` compiles the watch app's real
   `RideView` against `app/tool/store_watch/Stub.swift`, which takes its
   figures from the environment, and shoots it on an Apple Watch Ultra 3
   simulator with the figures the phone showed, so the two agree.
3. **Slides.** `app/tool/store_slides.py` builds each slide with headless
   Chrome in the website's hero style: an eyebrow chip, a sentence-case
   headline with the accent phrase, a subline, accent glows over contour
   lines, and the screenshot in a phone frame. Every slide is made in both
   styles, `dark` and `light`, each showing the app in the matching theme
   unless `--shots` says otherwise.

Five layouts: `phone`, running off the bottom edge; `whole`, the phone sized
to show all of the screen; `watch`, the phone beside the Apple Watch app's
riding screen; `lock`, the Lock Screen with the ride's Live Activity and the
expanded Dynamic Island, drawn after `app/ios/VelorkiLiveActivity/` with the
figures the test saved (the simulator cannot show a Live Activity on its Lock
Screen); `split`, the same screen light and dark, cut diagonally below the copy, the
dark half in another accent.

watchOS keeps its own clock whatever the simulator's status bar is told, so
the watch slide paints 9:41 over it, as the phone shows.

Copy and order live in `app/store/`:

- `slides_en.json`: per slide an `eyebrow`, a `headline` with the accent
  phrase in `**`, and a `subline`. Other languages are `slides_<lang>.json`
  from Crowdin; a slide missing there falls back to English. A headline that
  runs past three lines, or a subline past two, shrinks to fit.
- `slide_set.json`: the set that is uploaded, in order, and per slide its
  layout, the screen it shows and its style. Changing the mix is an edit
  there and `--skip-capture`.

Output, git-ignored, under `app/build/store_screenshots/`:

- `raw/<theme>/<locale>/<screen>.png`, 1320 × 2868
- `watch/<theme>/<locale>/riding.png`, 422 × 514
- `slides/<style>/<size>/<locale>/<slide>.png`, every slide in both styles
- `slides/set/<size>/<locale>/NN-<slide>.png`, the set to upload
- `slides/set/contact-<locale>.png`, the set side by side

## Adding a language

1. The app strings, the store texts and `slides_<lang>.json` arrive through
   Crowdin.
2. If the store's region for the language is not in `region_of` in
   `store_screenshots.sh`, and to `store_watch.sh`, add it.
3. `app/tool/store_screenshots.sh --locales <lang>`.

## Uploading

In App Store Connect, the version's page, per localization:

| Folder | Field |
|---|---|
| `slides/set/6.9/<locale>/` | iPhone 6.9" Display |
| `slides/set/6.5/<locale>/` | iPhone 6.5" Display |

Upload them in file order; ten is the most a size takes. A localization
without its own screenshots shows the primary language's.

The App Store shows one set of screenshots whatever the viewer's appearance.
Product Page Optimization (App Store Connect → the app → Product Page
Optimization) runs another set, such as all-dark or all-light, as a treatment
against it, to see which converts better.
