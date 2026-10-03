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
app/tool/store_screenshots.sh [--locales en,de] [--themes light,dark] [--shots same|light|dark]
                              [--until <screen>] [--skip-capture]
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
   simulator with the figures the phone showed, so the two agree: once for
   the slide, and in four states for the App Store's Apple Watch
   screenshots (riding with the next turn, riding, paused, no ride), with
   the heart held still rather than caught mid-pulse and the figures of
   `app/store/watch_store.json`.
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
  layout, the screen it shows and its style; `brand` puts the app's icon and
  name above the eyebrow (slide 01 only). The preview's first caption card
  carries them too. Changing the mix is an edit
  there and `--skip-capture`.

`--until plan` or `--until variants` captures only the screens up to that
one (the test takes them in the order plan, variants, loop, import, ride,
library, offline, live) and keeps the rest of the last capture.

Output, git-ignored, under `app/build/store_screenshots/`:

- `raw/<theme>/<locale>/<screen>.png`, 1320 × 2868
- `watch/<theme>/<locale>/riding.png`, 422 × 514, for the slide
- `watch/<theme>/<locale>/store/{1-riding-turn,2-riding,3-paused,4-idle}.png`,
  the Apple Watch screenshots
- `slides/<style>/<size>/<locale>/<slide>.png`, every slide in both styles
- `slides/set/<size>/<locale>/NN-<slide>.png`, the set to upload
- `slides/set/contact-<locale>.png`, the set side by side

## Google Play

```
app/tool/store_screenshots.sh --platform android [--locales en,de] [--themes light,dark]
```

The same test on an Android emulator, for the screens the Play set uses.
Start one first: a Pixel 6 profile (1080 × 2400) on a `google_apis` image,
e.g. an AVD made with `avdmanager create avd -n Velorki_Shots_Android -d
pixel_6 -k "system-images;android-35;google_apis;arm64-v8a"` and started with
`emulator -avd Velorki_Shots_Android -gpu swiftshader_indirect`.
`VELORKI_STORE_EMULATOR` names its adb serial when more than one runs. Per
language the script sets the emulator's locale (`adb root`, then a reboot
when it changes), switches on the hole-punch cutout and gesture navigation,
and sets SystemUI's demo mode: 9:41, full wifi, a full battery, no
notifications, and no network at all for the offline shot. The demo mode's
mobile icon is left out: on API 35 it keeps a stale "3G" and the wrong tint.
`tool/store_shutter.py --android` answers the test through `adb shell run-as`
(the request lies in the app's `files/itest/`) and takes the pictures with
`adb exec-out screencap`. The mirror is reached as `10.0.2.2`. No watch, Lock
Screen or preview.

`app/tool/store_slides.py --platform android` lays the slides out at
1242 × 2484, the phone frame taking the capture's shape. The set is
`app/store/slide_set_android.json` (eight slides, no watch or Lock Screen); a
slide's `android` object in `slides_<lang>.json` overrides its copy there
(the plan's subline names no phone). Beside the set it makes the 1024 × 500
feature graphic (the brand line and `feature.headline` over the dark plan)
and a 512 × 512 icon from the app icon, and fails on a PNG Play would refuse.

What Play wants: 2 to 8 phone screenshots per language, PNG or JPEG without
alpha, each side 320 to 3840 px, the long side at most twice the short one,
up to 8 MB each; a 1024 × 500 feature graphic; a 512 × 512 icon.

Output, git-ignored, under `app/build/store_screenshots/android/`:

- `raw/<theme>/<locale>/<screen>.png`, 1080 × 2400
- `slides/<style>/android/<locale>/<slide>.png`, every slide in both styles
- `slides/set/<locale>/NN-<slide>.png` and `feature-graphic.png`, to upload
- `slides/set/contact-<locale>.png` and `slides/set/icon-512.png`

Uploading is by hand for now, in the Play Console under the store listing,
per language: the set as phone screenshots in file order, the feature
graphic and the icon. An upload from CI (fastlane `supply`) comes once the
app has a Play account.

## Preview video

```
app/tool/store_screenshots.sh --preview [--locales en]
python3 app/tool/store_preview.py --locales en --frame phone   # the other framing, from the same clips
```

One app preview per language, about 28 s: five clips of the real app, each
with the eyebrow and headline of a slide, joined by 0.3 s crossfades.

1. **Recording.** `app/integration_test/store/store_preview_test.dart` plays
   each clip on the same simulator and demo data as the screenshots, and
   `tool/store_shutter.py` records the screen around it with `simctl io
   recordVideo`: the route drawing in point by point, the variants loaded and
   switched, a loop found, the 20 km ride navigating through a turn close up
   (heading-up, one fix a second of ride time), and that ride finished, saved
   and its charts scrolled. The charts are scrolled without touching them, so
   no chart ever shows a selection.
2. **Cutting.** `app/tool/store_preview.py` plays a clip that runs long up to
   1.5 times as fast and keeps its end, puts the caption on, crossfades the
   clips and encodes the result. Two framings of the same clips:
   - `none` (the default): the app full-bleed, with the caption on a
     floating frosted card like a notification: the app behind it blurred
     and tinted ink or paper, a hairline border, a soft shadow. A top card
     covers the status bar and search field and ends above the planner's
     bike chips; a bottom one ends above the figures bar, clear of the turn
     banner. It slides and fades in `caption_delay` seconds after the
     crossfade into its clip (1 s by default), holds for
     `caption_hold` seconds (both can be set per clip), and
     slides out, so the rest of each clip shows the app alone;
   - `phone`: the app scaled whole below the caption on the slides' ground.

The card's look is `card` in the set: `accent-frame`, the default
(the frosted card with a 4 px accent border and an accent glow, so it reads
as an overlay rather than a panel of the app), `frost` (without them) or `accent-solid` (an opaque
card in the accent colour, lime with ink text on dark scenes, deep green with
white text on light ones). `store_preview.py --card <name>` renders another
one from the same clips as `preview-<name>.mp4`.

`app/store/preview_set.json` sets the framing, the card, the clip the poster comes
from, and per clip, in the order they play, its theme, the slide its caption
comes from, `caption` (`top` or `bottom`) and its seconds. It opens on
navigation, the scene with the most movement. The captions are the slides'
copy, so they arrive through Crowdin with `slides_<lang>.json`.

Output, git-ignored: `app/build/store_screenshots/preview/<locale>/`
`preview.mp4` (or `preview-phone.mp4`), `poster.png` and `frames/` (stills
every few seconds, to look at before uploading). The raw clips are in
`raw/preview/<locale>/`.

What Apple says, in its app preview specifications and guidelines:

- 15 to 30 s; up to three previews per language and device size.
- 886 × 1920 portrait for the 6.9", 6.5", 6.3" and 6.1" iPhone sizes alike;
  the 5.5" size wants 1080 × 1920.
- Up to 30 fps; H.264 High Profile level 4.0 at 10 to 12 Mbit/s (this one
  holds 11), `.mp4`, `.mov` or `.m4v`, at most 500 MB.
- A stereo AAC track at 256 kbit/s, 44.1 or 48 kHz; this one is silent.
- "App previews must show only content within the app itself", and App
  Review guideline 2.3.4 asks for "video screen captures of the app itself".
  Captions and transitions are allowed; people and hands are not. Device
  frames are not named, which is why `none` is the default.
- Previews play muted, so the first seconds and the captions carry them. The
  poster frame is chosen in App Store Connect, at 5 s by default.

It goes into App Store Connect under the version's page, per localization,
in the App Previews and Screenshots section of the 6.9" iPhone display,
beside the screenshots.

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
| `watch/<theme>/<locale>/store/` | Apple Watch (Ultra), as JPEG: the store refuses the PNGs' alpha channel |

Upload them in file order; ten is the most a size takes. A localization
without its own screenshots shows the primary language's.

Or from CI, below.

The App Store shows one set of screenshots whatever the viewer's appearance.
Product Page Optimization (App Store Connect → the app → Product Page
Optimization) runs another set, such as all-dark or all-light, as a treatment
against it, to see which converts better.

## In CI

`.github/workflows/store-assets.yml`, started by hand (Actions → store assets
→ Run workflow), runs `store_screenshots.sh` for the `locales` given, and with
`preview` the preview too, on a macOS runner. The artifact `store-assets`
holds `slides/set/` (both sizes, every language, the contact sheets),
`watch/` and `preview/<locale>/preview.mp4` with its poster. The `ios` and
`android` inputs choose the sets; `android` runs `--platform android` on an
API 35 emulator on Ubuntu (integration.yml's setup and caches) into the
artifact `store-assets-android` (`android/slides/set/`). The runner's
simulator has no GPU and drops frames of the moving map (a third in the
navigation scene), so the preview for the store is recorded on a Mac with
`--preview`; `preview` stays off unless asked for.

With `upload`, the run must be started from a `v*` tag, with `app_version`
the App Store version to fill (created if it does not exist yet). The
`upload` job waits in the `release` environment for the maintainer's
approval, then `app/tool/store_stage_deliver.sh` lays the set out per store
locale and `fastlane ios store_assets` (deliver, with the App Store Connect
API key) replaces that version's 6.9", 6.5" and Apple Watch screenshots in
each language uploaded, the watch getting the four `store/` shots.
`metadata` also uploads `app/fastlane/metadata/ios`. Nothing is submitted for
review. The preview video is uploaded by hand, from the Mac's recording.
