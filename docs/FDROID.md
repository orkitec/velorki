# The F-Droid flavour

A build of Velorki with no closed-source library in it: nothing from
`com.google.android.gms`, `com.google.android.play`, `com.google.firebase`,
`com.android.billingclient` or `com.revenuecat` reaches the dex. It is what
F-Droid can publish and what runs on a phone with no Google Play Services at
all.

It is the same app. Planning, offline maps and on-device routing, search,
turn-by-turn with voice, ride recording, Bluetooth sensors, GPX/FIT/TCX, the
offline cycle map and the free weather map are all the app's own code over
OpenStreetMap data and free plugins, and all of them are in this build.

What is not, because only a closed-source library can do it:

| Gone | Why |
|---|---|
| Velorki Plus, and every entry point for it | `purchases_flutter` (RevenueCat) over Play Billing. Not a paywall that says no — nothing at all: no Plus row in Settings, no Ask button or AI assistant, no AI settings, no share link row, no relay radar or route forecast, no paywall to reach. Nobody can buy Plus here, so each of those is a dead end, and a dead end naming a paid add-on is what a store reads as an advertisement for one. `plusOfferedProvider` is the single switch; `main_fdroid.dart` overrides it to false and `offeredPlusFeaturesProvider` goes empty, which every entry point already asks. Plus bought in the Play or App Store build still works on that install. |
| Google Drive sync | `google_sign_in` + `googleapis`. Settings → Sync with offers nothing on Android in this build. |
| The store's rating dialog | `in_app_review`. Never asked for. |
| The update notice | `in_app_update`. F-Droid updates the app itself. |
| The Apple Watch link, the lock-screen card | `watch_connectivity`, `live_activities` — iOS only in any case. |

And one thing that is left out by choice rather than by licence:

**Strava and Ride with GPS are not in the first F-Droid submission.** Nothing
technical stops them — the code is pure Dart over a browser OAuth flow and is
compiled into this build exactly as into the store builds — but
`env/fdroid.json` carries no client id for either, and a service with no
client id is left out of the interface entirely: no Connections row in
Settings, no import action in the Library, no share rows. They may come back
in a later submission; putting the ids into `env/fdroid.json` is the whole
change. `app/test/app/fdroid_config_test.dart` reads that file and pins what
it means, so an id added to it without the rest of the thinking fails the
suite.

## How it is built

Two facts shape the whole design:

- **Flutter compiles the Android half of every plugin in `pubspec.yaml`,
  whether Dart calls it or not.** So the six plugins have to be *removed from
  `pubspec.yaml`* for this build. Guarding them behind a flag in Dart would
  change nothing in the dex.
- **Dart compiles only what the entry point reaches.** So a second entry point
  whose import graph never reaches those plugins can be compiled from a
  pubspec that no longer lists them.

That gives three pieces:

1. **Every provider's default is the free implementation.** Six providers used
   to pick the proprietary implementation themselves; now each defaults to the
   free one (or to null), and the proprietary one is a `ProviderScope`
   override. `app/lib/app/proprietary_services.dart` is the one file that
   reaches those plugins, and `bootstrap.dart` is the only file that imports
   it. The rule to keep: **no file reachable from a bare provider import may
   import a proprietary plugin.**

   | Provider | Default | Override |
   |---|---|---|
   | `subscriptionServiceProvider` | `NoopSubscriptionService` | `storeSubscriptionOverride()` |
   | `googleSignInServiceProvider` | `null` | `googleCloudOverrides()` |
   | `googleDriveStoreProvider` | `null` | `googleCloudOverrides()` |
   | `reviewRequestProvider` | a no-op | `storePromptOverrides()` |
   | `storeUpdateSourceProvider` | the App Store lookup on iOS, else `null` | `storePromptOverrides()` |
   | `watchGatewayProvider` | `null` | `watchGatewayOverride()` |
   | `rideLiveActivityProvider` | `NoRideLiveActivity` | `liveActivityOverride()` |

   The App Store's version lookup stays in the default: it is plain HTTP
   against Apple's public API, no SDK.

2. **`app/lib/main_fdroid.dart`**, the entry point. It calls the shared
   `startVelorki()` (`app/lib/app/startup.dart`) with no overrides, where
   `main.dart` goes through `bootstrap.dart` and passes all of them. It also
   sets `googleServicesAvailable = false`
   (`app/lib/app/build_flavour.dart`), which is the one thing a provider
   cannot carry: it tells geolocator to ask the Android `LocationManager`
   rather than the fused provider.

3. **`app/tool/fdroid_strip.sh`**, which turns a checkout into the tree that
   build compiles — so F-Droid's own recipe stays three lines and the whole
   thing can be tested on a laptop. It takes the six plugins out of
   `pubspec.yaml` and `pubspec.lock`, and **patches the pub cache in place**
   for the two plugins Velorki keeps that reference Google Play Services:

   - `geolocator_android`: drop the `play-services-location` dependency,
     delete `FusedLocationClient.java`, reduce `createLocationClient` to the
     `LocationManagerClient`.
   - `maplibre_gl`: drop `play-services-base` and `-location`, delete
     `GMSLocationEngine.java`, make `LocationEngineFactory` always use
     `MapLibreGPSLocationEngine`. From maplibre_gl 0.28 there is a
     `maplibre_gl.playServicesLocation=false` Gradle property that does this
     without a patch; the script sets it instead as soon as the app moves up.

   Both fall back to the free client by themselves on a phone without Play
   Services — the patch is not about behaviour, it is about the *reference*
   being gone.

   It ends by grepping the patched sources and failing if
   `com.google.android.gms` is left. It is idempotent.

## Building it

```sh
cd app
bash tool/fdroid_strip.sh                       # modifies the pub cache
flutter build apk --release --target lib/main_fdroid.dart \
  --dart-define-from-file=env/fdroid.json
bash tool/fdroid_scan.sh build/app/outputs/flutter-apk/app-release.apk
```

`fdroid_strip.sh` leaves `$PUB_CACHE` (or `~/.pub-cache`) patched for every
other project on the machine until `flutter pub cache repair`. Give it a cache
of its own if that matters:

```sh
PUB_CACHE=$PWD/.pub-cache bash tool/fdroid_strip.sh
```

`env/fdroid.json` holds no secret: the relay's URL, the tile mirror, the map
styles, and empty strings for everything to do with a store, a Google account
or a partner service. The empty Strava and Ride with GPS client ids are
deliberate, not a gap to fill — see above.

## What keeps it honest

Three things, in rising cost:

A Google-free Android is usually in one of two states the voice list now
tells apart, in Settings → Navigation → Voice. **No engine at all** (a plain
AOSP build, LineageOS): install one, with eSpeak NG and RHVoice named as
examples; the old line, "add a voice in the phone's settings", is advice for
a page such a phone does not have. **An engine without the rider's language**:
GrapheneOS ships its own speech services, on by default, which speak US
English and nothing else, so a rider riding in German has an engine and no
voice. That line names the language and says either add one if the engine
offers it or install another. Both asked of the phone
(`speechEngineInstalledProvider`), not of the flavour, so every Android build
says them where they are true. Navigation itself has always
been safe there: the first cue fails with `SpeakError.engineUnavailable`,
`SpeakTurnSpeaker` marks itself broken and the ride simply runs in silence.

Settings → About carries one short note in this build and no other
(`settingsFlavourTitle`/`settingsFlavourBody`, behind the same
`plusOfferedProvider`): what the version is and what it leaves out, naming
F-Droid and no other store, with no link and nothing to tap.

The free weather map the phone fetches itself is untouched: only the relay's
radar composites and the route forecast go, and they were already behind
"Plus granted", which this build never is.

**The unit suite**, on every push. `app/test/app/proprietary_services_test.dart`
pins both halves of each of the seven providers: the free default an
unoverridden container gets (which is the whole of the F-Droid build) and the
concrete proprietary type `proprietaryServiceOverrides()` installs over it, so
an override dropped in a refactor fails rather than quietly shipping the free
service to the stores. `app/test/app/entry_points_test.dart` keeps the two
entry points from drifting — neither may start the app itself, only
`startup.dart` and the browser's `bootstrap_web.dart` call `runApp` — and
walks the import graph from `lib/main_fdroid.dart` asserting that nothing it
reaches imports one of the eleven packages the strip removes. That last check
is the contract this whole design rests on, and it fails in a second, without
a build.

**The `fdroid` job** in `.github/workflows/app.yml`, on every push that
touches `app/`: `app/tool/fdroid_build.sh` strips, builds from
`lib/main_fdroid.dart`, and `app/tool/fdroid_scan.sh` unpacks the APK and fails
if any dex names one of the five package paths. The same script builds it on a
laptop (`build/fdroid/velorki-fdroid-release.apk`): it keeps the patched
plugins in a pub cache of its own under `.dart_tool/` and puts `pubspec.yaml`
and `pubspec.lock` back on every exit. An eighth proprietary plugin added to `pubspec.yaml`
without the same treatment turns that job red.

**A device.** The `fdroid` job in `.github/workflows/integration.yml` — the
same trigger as the rest of the emulator suite, pushes to main that touch
`app/` and nightly — strips the build and runs **the whole emulator suite**
on an AOSP (`default`) system image, API 35, which has no Google Play
Services on it at all, split three ways as the Android job is.
`VELORKI_ITEST_FDROID=1` is what tells `app/tool/itest.sh` to skip the files
that import a plugin the strip took out — the list comes from
`app/tool/fdroid_plugins.sh`, the one the strip itself uses, so the two cannot
drift — and to lead shard 1 with
`app/integration_test/fdroid_smoke_test.dart`, so a broken build fails in
minutes rather than twenty. Today that skips `live_ride_test.dart` and
`live_navigate_test.dart`, both of which read the Live Activity on an
iPhone's lock screen. The smoke test itself starts
the app, reads every one of the seven providers (each a plugin that is simply
not in that APK), takes a real position off the platform's own
`LocationManager`, checks that no Plus entry point is shown, downloads the
region's rd5 from the runner's mirror, routes on the device, and records a ride
of 200 m off the platform's GPS. For that file alone `itest.sh` grants the
location permission (`app/tool/grant_location.sh`) and moves the emulator with
`app/tool/emu_ride.py` in its `VELORKI_EMU_GEOFIX=1` mode: the AOSP image
ignores `geo nmea`, so plain `geo fix` points.
`app/tool/itest_fdroid.sh` is the same thing by hand. The file is in the
ordinary sweep and in `all_tests.dart` too, where it runs against an
unstripped build on a Google image and skips itself off Android.

One thing the scan does not catch: a *string* that mentions a store. The
paywall's Google Play renewal terms (`plusLegalPlay`) are compiled into the
binary with the rest of the localisations, but this build has no way to the
paywall at all (`plusOfferedProvider` is false), so no rider sees them.
