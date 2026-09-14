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
- [x] **(iOS)** `pausesLocationUpdatesAutomatically = false` and the background
      location indicator is enabled. —
      `lib/features/recording/data/recording_positions.dart`
      (`pauseLocationUpdatesAutomatically: false`,
      `showBackgroundLocationIndicator: true`).
- [x] **(iOS)** `PrivacyInfo.xcprivacy` is present and lists the required-reason
      APIs actually used. — `ios/Runner/PrivacyInfo.xcprivacy`: UserDefaults
      `CA92.1` and file timestamp `C617.1`. **It still has to be added to the
      Runner target in Xcode**, see the Mac list at the end; a file that is not
      in Copy Bundle Resources is not in the app.
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

What leaves the device: routing waypoints, search queries, map tile requests,
the AI prompt with a coarse start position, the RevenueCat anonymous app user
id and purchase receipts, and — only on user action — rides and routes to
Strava or RideWithGPS, and shared routes to our share store.

- [x] **(iOS)** The privacy manifest in the bundle declares precise location,
      purchase history, the RevenueCat user id and other user content, all
      "app functionality", none linked to identity, none used for tracking. —
      `ios/Runner/PrivacyInfo.xcprivacy`. The App Privacy **answers in App
      Store Connect must say the same**; the four boxes below are those
      answers.
- [ ] **(iOS)** App Privacy answers declare **precise location** (app
      functionality; not linked to identity; not used for tracking).
- [ ] **(iOS)** App Privacy answers declare **purchases** (RevenueCat).
- [ ] **(iOS)** App Privacy answers cover the RevenueCat anonymous app user id
      as an identifier.
- [ ] **(iOS)** App Privacy answers cover the **AI prompt text** (user content)
      and the coarse start position sent with it.
- [ ] **(Play)** The Data safety form mirrors all of the above, including who
      the data is shared with: the routing server, Photon, OpenFreeMap/CyclOSM,
      the AI provider, RevenueCat, and Strava/RideWithGPS on user action.
- [ ] Both forms state that no account is created and no data is used for
      tracking or advertising.
- [ ] The forms match `docs/PRIVACY.md` word for word on what is collected.
- [ ] No accounts means: **no** account-deletion flow and **no** Sign in with
      Apple requirement. Confirm the review notes say so.
- [x] **(Play)** Rides, routes and tokens are kept out of Google backup and
      out of device-to-device transfer, so "data is encrypted in transit" and
      the backup answers stay honest. — `android:allowBackup="false"` plus
      `res/xml/data_extraction_rules.xml`.
- [x] **(iOS)** No tracking, so `NSUserTrackingUsageDescription` is
      deliberately **not** in `Info.plist` and no ATT prompt is shown.

## Privacy policy

- [ ] A public privacy policy URL is live. — `https://velorki.app/privacy`
      must be published; nothing serves it yet.
- [x] It is linked from the app: Settings → About → "Privacy policy", and from
      the paywall. — `lib/features/settings/presentation/about_section.dart`,
      `lib/core/links/velorki_urls.dart`.
- [ ] It is linked from both store listings (the URL field in each console).
- [x] It names the AI provider, Strava, RideWithGPS, RevenueCat, the map tile
      provider and the search provider. — `docs/PRIVACY.md`; the AI section
      now says "OpenAI (or the provider configured by the operator)", the
      relay being OpenAI-compatible.
- [x] It states retention for share links (one year) and that uninstalling
      removes local data. — `docs/PRIVACY.md`, "Retention and deletion".
- [ ] It has been reviewed by a lawyer (`docs/PRIVACY.md` is a draft).
- [ ] The crash-reporting section is resolved rather than "to be decided".
- [ ] The server-log retention period is filled in, and so are the controller's
      postal address and, if one is needed, the data protection representative.

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
- [ ] The assistant's scope is constrained to route planning, and the
      age-rating questionnaire answers reflect that.
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
- [ ] The 7-day free trial is configured in both stores and in RevenueCat.
- [ ] Sandbox purchase, renewal, cancellation and restore-after-reinstall are
      all tested on both platforms.
- [x] Every gated feature unlocks through in-app purchase only; there is no
      external payment link. — `lib/core/plus/plus_gate.dart` is the single
      list of gated features, and nothing in the app links to a payment page.
- [ ] A lapsed subscription hides the integrations and keeps all user data.
      Verify on a real expiry or a sandbox cancellation.

## Age rating

- [ ] The App Store age-rating questionnaire is completed, including the
      questions about AI assistants and user-generated content.
- [ ] The Play content-rating questionnaire (IARC) is completed.
- [ ] Expected outcome is 4+ / Everyone; if the answers push it higher,
      re-check the assistant's constraints before accepting the rating.

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

- [ ] An API key has been requested and granted through their form.
- [ ] The OAuth redirect URI is registered and matches the app's scheme
      (`velorki://oauth/rwgps`).
- [ ] Their branding and attribution requirements have been reviewed and
      followed.

## Icons, splash and store graphics

- [x] The app icon is generated for both platforms from committed SVGs. —
      `app/assets/icon/icon.svg` → `icon.png` and `icon_foreground.svg` →
      `icon_foreground.png` →
      `dart run flutter_launcher_icons` (configured in `app/pubspec.yaml`:
      `android: true`, `ios: true`, adaptive background `#1B7F5A`, adaptive
      foreground, `remove_alpha_ios: true`). Regeneration steps:
      `app/assets/icon/README.md`.
- [x] The iOS icon has no alpha channel (App Store rejects one). —
      `remove_alpha_ios: true`, and the source square is opaque and full bleed
      because both platforms apply their own corner mask.
- [x] The Android launch screen is the seed colour instead of a white or black
      flash. — `res/values/colors.xml` (`velorki_splash_background`),
      `res/drawable{,-v21}/launch_background.xml`, and
      `android:windowSplashScreenBackground` in `res/values{,-night}/styles.xml`
      for the Android 12+ splash screen. No splash package is used.
- [ ] Store icon exports are uploaded: **512 × 512** for Play, **1024 × 1024**
      for App Store Connect, both without transparency. Generated on demand
      from the same SVG, see `app/assets/icon/README.md`; they are not
      committed.
- [ ] Screenshots: at least 2 (Play, phone) and the required sizes for iPhone
      6.9" and 6.5". Plan, loop result, recording and library are the four
      screens worth showing.
- [ ] **(Play)** Feature graphic, 1024 × 500.

## Accounts and store administration

- [ ] Check whether the Orkitec Google Play developer account is **personal** or
      **organisation**: a personal account requires a 14-day closed test with at
      least 12 testers before production access. Plan the timeline accordingly.
- [ ] App signing is configured (Play App Signing; iOS signing via fastlane
      `match`). — the lanes exist (`app/fastlane/Fastfile`), the keystore, the
      match repository and the App Store Connect API key do not.
- [x] Store listing copy exists as a first draft. —
      `app/fastlane/metadata/android/en-US/{title,short_description,full_description}.txt`
      and `app/fastlane/metadata/ios/en-US/{name,subtitle,description,keywords}.txt`,
      inside the character limits. **Draft**: not reviewed, prices not final,
      and both upload lanes run with metadata upload switched off so a release
      cannot overwrite the consoles by accident.
- [x] Export compliance: the app uses only standard HTTPS/TLS, so the exemption
      applies. `ITSAppUsesNonExemptEncryption = false` is set in `Info.plist`.
- [ ] Answer the Play export declaration (US export laws) accordingly.

## App Review notes

Write review notes covering:

- [ ] Why background location is needed (recording a ride with the screen off)
      and how to reproduce it.
- [ ] That there are no accounts, so no demo credentials are needed.
- [ ] How to reach the AI assistant and that it is behind a subscription, with
      a sandbox/promo note on how the reviewer can try it.
- [ ] Where the privacy policy and the AI consent screen are.
- [ ] That map data is OpenStreetMap and routing is self-hosted BRouter.

## What is left, and where to do it

Everything above that is still open, grouped by where the work happens.

### In Xcode, on the Mac

Add `ios/Runner/PrivacyInfo.xcprivacy` to the **Runner** target: select the file
in the navigator, File inspector → Target Membership → Runner, and check it
appears under Runner → Build Phases → Copy Bundle Resources. Until then the
manifest is in the repository but not in the app. The rest of the Mac work —
the Share Extension target, `fastlane match` — is in
[OPEN_ITEMS.md](OPEN_ITEMS.md).

### In App Store Connect

| What | Where |
|---|---|
| App Privacy answers (precise location, purchases, user id, user content) | App → App Privacy → **Get Started / Edit**, one card per data type; they must match `ios/Runner/PrivacyInfo.xcprivacy` |
| Age rating | App → **App Information** → Age Rating → Edit; answer the AI and user-generated-content questions for a constrained planner |
| Privacy policy URL | App → **App Information** → Privacy Policy URL, and App Privacy → Privacy Policy |
| Terms of use (EULA) | App → **App Information** → License Agreement, or the standard EULA plus the paywall link |
| Subscriptions and the 7-day trial | **Monetization → Subscriptions**: one group, monthly and yearly, an introductory offer of seven days free, and the same product ids in RevenueCat |
| Export compliance | Asked per build; `ITSAppUsesNonExemptEncryption = false` answers it in advance |
| Review notes | App → the version → **App Review Information** → Notes |
| Screenshots | App → the version → Previews and Screenshots, 6.9" and 6.5" iPhone |

### In the Play Console

| What | Where |
|---|---|
| Data safety | **Policy → App content → Data safety**; declare location, purchases, the RevenueCat id and the AI prompt text, all "app functionality", none for tracking or advertising, and list the recipients |
| Sensitive permissions / background location | **Policy → App content → Sensitive app permissions**; nothing to declare while `ACCESS_BACKGROUND_LOCATION` stays out of the manifest, but the page has to be answered |
| Location "Minimum Scope" declaration | **Policy → App content**, before November 2026 |
| Content rating (IARC) | **Policy → App content → Content rating** |
| Target audience, ads, government apps, financial features | **Policy → App content**, the remaining cards; all "no" |
| Export compliance | **Policy → App content → US export laws** |
| Privacy policy URL | **Grow → Store presence → Store listing**, and App content → Privacy policy |
| Service account for `supply` | Google Cloud console → service account → key, then **Users and permissions** in the Play Console with the *Release manager* role; the path goes into `PLAY_SERVICE_ACCOUNT_JSON_PATH` (see `app/fastlane/README.md`) |
| Subscriptions and the 7-day trial | **Monetize → Products → Subscriptions**, matching the RevenueCat product ids |
| Internal testing track and, if the account is personal, the 14-day closed test with 12 testers | **Test and release → Testing** |
