# Store checklist

Release-blocking items for the App Store and Google Play. Nothing here is
optional: each box has either blocked a review in the past or is required by a
policy that applies to this app.

Legend: **(iOS)** App Store only, **(Play)** Google Play only, no marker =
both. A ticked box names the file or the screen that makes it true, so the
claim can be checked without hunting.

Everything still unticked is a form in one of the two consoles, collected in
[What is left, and where to do it](#what-is-left-and-where-to-do-it) at the end.
The engineering and account work is in [OPEN_ITEMS.md](OPEN_ITEMS.md).

## Background location

The app records rides with the screen off, so both stores treat it as a
background-location app.

- [x] **(iOS)** `NSLocationWhenInUseUsageDescription` is set and says the app
      records rides while they are in progress. — `ios/Runner/Info.plist`.
- [x] **(iOS)** `NSLocationAlwaysAndWhenInUseUsageDescription` is set if the
      significant-location-change relaunch stretch goal ships; otherwise it is
      deliberately absent. — deliberately absent; the stretch goal is not in
      v1, and "When In Use" is enough for a foreground recording.
- [x] **(iOS)** `UIBackgroundModes` contains `location`. —
      `ios/Runner/Info.plist`.
- [x] **(iOS)** `UIBackgroundModes` also contains `audio`, so a spoken turn cue
      is not silenced while the screen is locked. — `ios/Runner/Info.plist`;
      the playback audio session is set up in
      `app/lib/features/navigation/data/turn_speaker.dart`.
- [x] **(iOS)** `pausesLocationUpdatesAutomatically = false` and the background
      location indicator is enabled. —
      `lib/features/recording/data/recording_positions.dart`
      (`pauseLocationUpdatesAutomatically: false`,
      `showBackgroundLocationIndicator: true`).
- [x] **(iOS)** `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription`
      say heart rate is read for rides and rides are saved as workouts, and the
      HealthKit entitlement is on Runner and on the watch app. Nothing asks
      until the Health switch in Settings → Sensors is turned on, which is what
      Apple's HealthKit review guideline wants. — `ios/Runner/Info.plist`,
      `ios/Runner/Runner.entitlements`, `ios/VelorkiWatch/`.
- [x] **(iOS)** `NSBluetoothAlwaysUsageDescription` says the app connects to
      heart-rate straps, speed, cadence and power sensors; the prompt comes on
      the first scan from the Bluetooth sensors screen. — `ios/Runner/Info.plist`.
- [x] **(iOS)** Health data is not collected: heart rate from Apple Health
      and the workouts written there stay on the phone, and a ride's share
      link carries no heart rate, cadence or power. — `ShareService`.
- [ ] **(Play)** Health Connect: the permissions declaration form in the Play
      Console (**Policy → App content → Health apps**) with the privacy policy
      link, and `READ_HEART_RATE`, `WRITE_EXERCISE`, `WRITE_DISTANCE` explained
      as ride recording. The manifest declares them; the sheet is only raised
      by the Settings switch. — `android/app/src/main/AndroidManifest.xml`.
- [x] **(Play)** `BLUETOOTH_SCAN` carries `neverForLocation`, so the scan does
      not count as a location permission. — `AndroidManifest.xml`.
- [x] **(iOS)** `PrivacyInfo.xcprivacy` is present and lists the required-reason
      APIs actually used, in every bundle. — `ios/Runner/PrivacyInfo.xcprivacy`:
      UserDefaults `CA92.1` and `1C8F.1` (the App Group), file timestamp
      `C617.1`; `ios/VelorkiShare/` and `ios/VelorkiLiveActivity/` each carry
      their own with UserDefaults `1C8F.1`. All three are in Copy Bundle
      Resources.
- [x] **(Play)** `android:foregroundServiceType="location"` is declared on the
      recording service and the `FOREGROUND_SERVICE_LOCATION` permission is in
      the manifest. — `android/app/src/main/AndroidManifest.xml`.
- [x] **(Play)** Confirm the manifest does **not** request
      `ACCESS_BACKGROUND_LOCATION` (the service starts in the foreground; this
      avoids the stricter review). — audited 12 September 2026: the manifest
      requests `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`,
      `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`,
      `WAKE_LOCK` and `INTERNET`, and nothing else. If it ever does:
  - [ ] the Play background-location declaration form is filled in,
  - [ ] a demo video showing the in-app feature and the runtime prompt is
        uploaded,
  - [ ] the prominent in-app disclosure is shown **before** the runtime
        permission prompt.
- [x] **(Play)** A prominent in-app disclosure explains recording before the
      first location prompt, regardless of which permissions are requested. —
      `lib/features/map/presentation/location_rationale_dialog.dart`.
- [ ] **(Play)** The "Minimum Scope" location declaration is submitted before
      November 2026 (enforcement starts January 2027).
- [x] The notification shown during recording states what is happening and
      shows distance and time. — `lib/features/recording/data/recording_service.dart`
      (`notificationText: '0.0 km · 00:00'`, updated from each snapshot).
- [x] The battery-optimisation exemption prompt is shown at most once and the
      app works if it is declined. — `recording.batteryPromptShown` guards it
      in `lib/features/recording/presentation/recording_screen.dart`: the flag
      is written whichever button is pressed, and "Later" only skips the
      system prompt — the recording runs either way.

## Privacy labels and data safety

What leaves the device: routing waypoints, map tile requests, search queries
when the rider asks for an online search, the AI prompt with a coarse start
position, the RevenueCat anonymous app user id and purchase receipts, and —
only on user action — rides and routes to Strava or RideWithGPS, and shared
routes to our share store.

- [x] **(iOS)** The privacy manifest in the bundle declares precise location,
      purchase history, the RevenueCat user id, other user content and
      fitness (a shared ride's track with its times), all
      "app functionality", none linked to identity, none used for tracking. —
      `ios/Runner/PrivacyInfo.xcprivacy`. The App Privacy **answers in App
      Store Connect must say the same**; the five boxes below are those
      answers.
- [x] **(iOS)** App Privacy answers declare **precise location** (app
      functionality; not linked to identity; not used for tracking). — App Store
      Connect, done for 1.0.
- [x] **(iOS)** App Privacy answers declare **purchases** (RevenueCat). — App
      Store Connect, done for 1.0.
- [x] **(iOS)** App Privacy answers cover the RevenueCat anonymous app user id
      as an identifier. — App Store Connect, done for 1.0.
- [x] **(iOS)** App Privacy answers cover the **AI prompt text** (user content)
      and the coarse start position sent with it. — App Store Connect, done for
      1.0.
- [x] **(iOS)** App Privacy answers declare **fitness** (a ride shared as a
      link: its track, times, distance and ascent; no sensor values). — App
      Store Connect, done for 1.0.
- [ ] **(Play)** The Data safety form mirrors all of the above, including who
      the data is shared with: the routing server, Photon, OpenFreeMap/CyclOSM,
      the AI provider, RevenueCat, and Strava/RideWithGPS on user action.
- [x] **(iOS)** The App Privacy answers state that no account is created and
      no data is used for tracking or advertising, and match `docs/PRIVACY.md`
      on what is collected. — App Store Connect, done for 1.0.
- [ ] **(Play)** The Data safety form states the same and matches
      `docs/PRIVACY.md` word for word on what is collected.
- [x] No accounts means: **no** account-deletion flow and **no** Sign in with
      Apple requirement. — App Review notes, App Store Connect, done for 1.0.
- [x] **(Play)** Rides, routes and tokens are kept out of Google backup and
      out of device-to-device transfer, so "data is encrypted in transit" and
      the backup answers stay honest. — `android:allowBackup="false"` plus
      `res/xml/data_extraction_rules.xml`.
- [x] **(iOS)** No tracking, so `NSUserTrackingUsageDescription` is
      deliberately **not** in `Info.plist` and no ATT prompt is shown.
- [x] **(iOS)** Re-downloadable data is excluded from the backup, as Apple's
      data storage guidelines require: `<appSupport>/brouter` (tiles,
      gazetteers, profiles) is flagged `NSURLIsExcludedFromBackupKey` when it
      is created. — `lib/core/files/backup_exclusion.dart` over the
      `app.velorki/backup` channel in `ios/Runner/AppDelegate.swift`.

## Privacy policy

- [x] A public privacy policy URL is live. — `https://velorki.com/privacy`
      (and `/terms`, `/imprint`), published 27 September 2026.
- [x] It is linked from the app: Settings → About → "Privacy policy", and from
      the paywall. — `lib/features/settings/presentation/about_section.dart`,
      `lib/core/links/velorki_urls.dart`.
- [x] **(iOS)** It is linked from the App Store listing. — App Store Connect,
      done for 1.0.
- [ ] **(Play)** It is linked from the Play listing and App content → Privacy
      policy.
- [x] It names the AI provider, Strava, RideWithGPS, RevenueCat, the map tile
      provider and the search provider. — `web/content/*/legal/privacy.md`; the
      assistant goes through OpenRouter, restricted to providers that neither
      train on nor retain requests (set in the OpenRouter account).
- [x] It states retention for share links (one year) and that uninstalling
      removes local data. — `docs/PRIVACY.md`, "Retention and deletion".
- [ ] It has been reviewed by a lawyer (`docs/PRIVACY.md` is a draft).
- [x] The crash-reporting section is resolved rather than "to be decided". —
      "there is none", `web/content/en/legal/privacy.md`.
- [x] The server-log retention period is filled in, and so are the controller's
      postal address and, if one is needed, the data protection representative.
      — 14 days web server, 90 days application logs; controller in Berlin; no
      representative needed for an EU controller.

## AI features

- [x] A one-time consent screen appears before any prompt leaves the device
      (Apple 5.1.2(i)), storing `denied`, `textOnly` or `withLocation`. —
      `lib/features/assistant/presentation/ai_consent_dialog.dart`.
- [x] Consent is revocable in Settings and revoking it disables the assistant.
      — Settings → AI assistant,
      `lib/features/assistant/presentation/ai_settings_section.dart`.
- [x] The start position sent with a prompt is rounded to about 1 km and no
      identifiers are in the prompt. — `roundCoordinate` in
      `lib/features/assistant/domain/ai_consent.dart`.
- [x] A "report AI output" action exists (mailto). — `aiReportMailto` in
      `lib/features/assistant/presentation/assistant_strings.dart`, reachable
      from Settings → AI assistant → "Report AI output". It is **not** on the
      assistant sheet itself; put it there if a reviewer asks.
- [x] **(iOS)** The assistant's scope is constrained to route planning, and the
      age-rating questionnaire answers reflect that. — App Store Connect, done
      for 1.0.
- [ ] **(Play)** The content-rating (IARC) answers reflect the same scope.
- [ ] The description step can be turned off by the user.
- [x] AI descriptions are disabled for routes with `source == strava` (Strava's
      terms forbid AI use of their data). — `canDescribe` in
      `lib/features/assistant/application/route_description_controller.dart`.

## Purchases

- [x] A **Restore purchases** button is on the paywall and in Settings, and
      works without any login. — `paywall_screen.dart` and
      `plus_settings_section.dart`; RevenueCat runs with an anonymous app user
      id, so a restore needs nothing but the store account.
- [x] Price, billing period, renewal terms and trial length are shown on the
      paywall before purchase. — `paywall_screen.dart` (`priceString`,
      `plusPeriodLabel`, the trial line and the auto-renewal wording).
- [x] Links to the terms of use and the privacy policy are on the paywall. —
      `paywall_screen.dart`, from `lib/core/links/velorki_urls.dart`.
- [ ] **(iOS)** The 7-day free trial on the yearly plan only (monthly has none):
      the yearly subscription's introductory offer in App Store Connect.
- [ ] **(Play)** The 7-day free trial on the yearly plan only: offer
      `free-trial` on base plan `yearly`, active, then visible in RevenueCat.
- [ ] Sandbox purchase, renewal, cancellation and restore-after-reinstall are
      all tested on both platforms.
- [x] Every gated feature unlocks through in-app purchase only; there is no
      external payment link. — `lib/core/plus/plus_gate.dart` is the single
      list of gated features, and nothing in the app links to a payment page.
- [ ] A lapsed subscription hides the integrations and keeps all user data.
      Verify on a real expiry or a sandbox cancellation.

## Age rating

- [x] **(iOS)** The App Store age-rating questionnaire is completed, including
      the questions about AI assistants and user-generated content. —
      App Store Connect, done for 1.0.
- [ ] **(Play)** The content-rating questionnaire (IARC) is completed.
- [ ] **(Play)** Expected outcome is Everyone; if the answers push it
      higher, re-check the assistant's constraints before accepting the rating.

## Attribution and licences

- [x] "© OpenStreetMap contributors" is visible in a corner of the map on every
      map screen. — `lib/features/map/presentation/map_attribution.dart`.
- [x] The About screen credits BRouter, Photon, OpenFreeMap and CyclOSM. —
      `lib/app/licenses.dart`, registered from `bootstrap()`. (The map's own
      attribution line adds CyclOSM only while the overlay is on.)
- [x] An open-source licences screen lists all bundled dependencies and their
      licences. — Settings → About → "Open-source licences" opens Flutter's
      `showLicensePage` with the app name and version;
      `lib/features/settings/presentation/about_section.dart`.
- [ ] The CyclOSM overlay respects the OSMF tile policy: no bulk download, no
      pre-caching of raster tiles. Audit the offline-region download once more
      before submission — vector regions come from OpenFreeMap, and the raster
      overlay must stay out of them.
- [ ] `brouter/profiles` keeps BRouter's MIT header.
- [ ] The repository is AGPL-3.0-only. A GPL-family app is acceptable in the
      App Store and on Google Play only because Orkitec holds the copyright on
      the code and can also distribute it under the stores' terms. That breaks
      the moment code arrives from someone else: **never merge an outside
      contribution without a signed CLA** (`CLA.md`, enforced by
      `.github/workflows/cla.yml`). Before a submission, check that every
      commit since the last release came from a signed contributor.

## Strava brand and API rules

- [x] The connect button is Strava's official **"Connect with Strava"** asset,
      unmodified. — `app/assets/strava/btn_strava_connect_with_orange.png` and
      the white variant, drawn at their native 48 px height by
      `StravaConnectButton` in
      `lib/features/integrations/presentation/strava_brand.dart`. Provenance
      and the rules the code follows: `app/assets/strava/README.md`.
- [x] The **"Powered by Strava"** logo appears wherever Strava data is shown.
      — the footer of the Strava routes list,
      `lib/features/integrations/presentation/external_routes_screen.dart`.
- [x] The word "Strava" does not appear in the app name, the store title or the
      icon. — `fastlane/metadata/android/en-US/title.txt`,
      `fastlane/metadata/ios/en-US/{name,keywords}.txt` and
      `app/assets/icon/icon.svg`. It does appear in the long descriptions,
      which is allowed.
- [x] Every view of a Strava activity links back to that activity on Strava. —
      "View on Strava" in `lib/features/integrations/presentation/ride_upload_menu.dart`,
      opening the activity URL returned by the upload.
- [x] Strava data is shown only to the athlete it belongs to. — there are no
      accounts and no sharing of imported Strava content; the token lives in
      the device keychain.
- [x] The cached Strava route list is evicted after 7 days. —
      `ExternalRouteListCache.maxAge`; `purgeExpired()` runs in `bootstrap()`.
      (Routes the user has actually imported keep their `external_fetched_at`
      column and are the user's own data, not a cache.)
- [x] Strava data is never sent to the AI provider. — `canDescribe` refuses
      `RouteSource.strava`.
- [ ] The Strava API review is submitted before the app exceeds 10 connected
      athletes (self-service works up to 10).
- [ ] The developer account holds an active Strava subscription, as their
      API terms require.
- [ ] The base URL move to `api-v3.strava.com` on 2027-01-04 is scheduled.
- [x] The UI states clearly that a route cannot be created in Strava through
      the API, and offers "export GPX, then share" instead. — the
      "Strava cannot receive routes" dialog in
      `lib/features/integrations/presentation/route_send_menu.dart`.
- [x] **(iOS)** `LSApplicationQueriesSchemes` contains `strava`, so the
      app-to-app authorisation can check for the Strava app before falling
      back to the web flow. Without it `canOpenURL("strava://")` always
      answers false and every connection goes through Safari. —
      `ios/Runner/Info.plist`.

## RideWithGPS

- [x] An API key has been requested and granted through their form. — the
      RideWithGPS API client; the connection works in the app.
- [x] The OAuth redirect URI is registered and matches the app's scheme
      (`velorki://oauth/rwgps`). — the same API client.
- [x] Their branding and attribution requirements have been reviewed and
      followed. — reviewed with the API client; the connection works in the app.

## Icons, splash and store graphics

- [x] The app icon is generated for both platforms from committed SVGs. —
      `app/assets/icon/icon.svg` → `icon.png`, `icon_foreground.svg` →
      `icon_foreground.png` and `icon_monochrome.svg` → `icon_monochrome.png` →
      `dart run flutter_launcher_icons` (configured in `app/pubspec.yaml`:
      `android: true`, `ios: true`, **adaptive background `#3F7A00`** — the
      volt accent's light tone, the colour of the light icon tile — adaptive
      foreground, adaptive monochrome, `remove_alpha_ios: true`). Regeneration
      steps: `app/assets/icon/README.md`.
- [x] The Android 13 themed icon is provided. — the `<monochrome>` layer in
      `res/mipmap-anydpi-v26/ic_launcher.xml` and
      `res/drawable-*/ic_launcher_monochrome.png`, the glyph alone with the
      ring holes transparent so the launcher's recolouring keeps the shape.
- [x] The iOS icon has the dark and tinted appearances of iOS 18. — the two
      `appearances` entries for the 1024 image in
      `AppIcon.appiconset/Contents.json` with
      `Icon-App-1024x1024@1x-{dark,tinted}.png`. `flutter_launcher_icons`
      rewrites that file, so re-add them after every run.
- [x] The iOS icon has no alpha channel (App Store rejects one). —
      `remove_alpha_ios: true`, and the source square is opaque and full bleed
      because both platforms apply their own corner mask. Only the tinted
      appearance keeps an alpha channel, which is what iOS builds the tint from.
- [x] The launch screen is the app icon filling the screen — the tile colour
      with the glyph centred — instead of a white or black flash, in both
      themes. — Android: `res/values/colors.xml` and `res/values-night/colors.xml`
      (`velorki_splash_background`, `velorki_splash_glyph`),
      `res/drawable/splash_icon.xml` (the glyph, tinted from those colours),
      `res/drawable{,-v21}/launch_background.xml`,
      and `android:windowSplashScreenBackground` plus
      `android:windowSplashScreenAnimatedIcon` in `res/values{,-night}/styles.xml`
      for the Android 12+ splash screen. iOS: `LaunchScreen.storyboard` over the
      `LaunchBackground` colour set and the `LaunchImage` image set, both with
      an Any and a Dark appearance. No splash package is used.
- [x] **(iOS)** The 1024 × 1024 store icon, without transparency. — App Store
      Connect, done for 1.0.
- [ ] **(Play)** The 512 × 512 store icon, without transparency, is uploaded.
      Generated on demand from the same SVG, see `app/assets/icon/README.md`;
      it is not committed.
- [x] **(iOS)** Screenshots for iPhone 6.9" and 6.5". — App Store Connect, done
      for 1.0; from `app/tool/store_screenshots.sh`, see
      [STORE_ASSETS.md](STORE_ASSETS.md).
- [ ] **(Play)** At least 2 phone screenshots are uploaded (produced, upload by
      hand).
- [ ] **(Play)** Feature graphic, 1024 × 500.

## Accounts and store administration

- [ ] Check whether the Orkitec Google Play developer account is **personal** or
      **organisation**: a personal account requires a 14-day closed test with at
      least 12 testers before production access. Plan the timeline accordingly.
- [x] App signing is configured (Play App Signing; iOS automatic signing with
      the cloud-managed distribution certificate). — Play App Signing is on in
      the Play Console and the upload keystore is in the `release`
      environment's secrets for `release.yml`; iOS signs in `ios-release.yml`,
      set up per [RELEASE_IOS.md](RELEASE_IOS.md).
- [x] Store listing copy exists. —
      `app/fastlane/metadata/android/en-US/{title,short_description,full_description}.txt`
      and `app/fastlane/metadata/ios/en-US/{name,subtitle,description,keywords}.txt`,
      inside the character limits. Both upload lanes run with metadata upload
      switched off so a release cannot overwrite the consoles by accident.
- [x] **(iOS)** Export compliance: the app uses only standard HTTPS/TLS, so
      the exemption applies. `ITSAppUsesNonExemptEncryption = false` is set in
      `Info.plist`.
- [ ] **(Play)** Answer the export declaration (US export laws) accordingly.

## App Review notes

**(iOS)** The review notes cover the following. — App Store Connect, done
for 1.0.

- [x] Why background location is needed (recording a ride with the screen off)
      and how to reproduce it.
- [x] Why the `audio` background mode is needed (spoken turn cues during a
      guided ride with the screen locked) and how to reproduce it.
- [x] That there are no accounts, so no demo credentials are needed.
- [x] How to reach the AI assistant and that it is behind a subscription, with
      a sandbox/promo note on how the reviewer can try it.
- [x] Where the privacy policy and the AI consent screen are.
- [x] That map data is OpenStreetMap and routing is BRouter, on the phone.

## What is left, and where to do it

Everything above that is still open, grouped by where the work happens.

### In App Store Connect

| What | Where |
|---|---|
| The 7-day free trial on the yearly plan | **Monetization → Subscriptions** → the yearly subscription → Introductory Offers: free, one week; monthly has none |

### In the Play Console

| What | Where |
|---|---|
| Store listing: copy, 512 × 512 icon, phone screenshots, feature graphic | **Grow → Store presence → Main store listing**; copy from `app/fastlane/metadata/android/en-US/` |
| Privacy policy URL | **Policy → App content → Privacy policy**, `https://velorki.com/privacy` |
| Data safety | **Policy → App content → Data safety**; declare location, purchases, the RevenueCat id, the AI prompt text and fitness (a shared ride), all "app functionality", none for tracking or advertising, and list the recipients |
| Health Connect | **Policy → App content → Health apps**: the privacy policy link and `READ_HEART_RATE`, `WRITE_EXERCISE`, `WRITE_DISTANCE` explained as ride recording |
| Sensitive permissions / background location | **Policy → App content → Sensitive app permissions**; nothing to declare while `ACCESS_BACKGROUND_LOCATION` stays out of the manifest, but the page has to be answered |
| Location "Minimum Scope" declaration | **Policy → App content**, before November 2026 |
| Content rating (IARC) | **Policy → App content → Content rating**; answer for a constrained planner |
| Target audience, ads, government apps, financial features | **Policy → App content**, the remaining cards; all "no" |
| Export compliance | **Policy → App content → US export laws** |
| Closed test, if the account is personal: 14 days, 12 testers | **Test and release → Testing → Closed testing** |
| Production release | **Test and release → Production**, once the above is done; then `NEXT_PUBLIC_STORE_URL_ANDROID` on the website (see [OPEN_ITEMS.md](OPEN_ITEMS.md)) |
