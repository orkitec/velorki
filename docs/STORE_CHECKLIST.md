# Store checklist

Release-blocking items for the App Store and Google Play. Nothing here is
optional: each box has either blocked a review in the past or is required by a
policy that applies to this app. Milestone M7 is "all boxes ticked".

Legend: **(iOS)** App Store only, **(Play)** Google Play only, no marker =
both.

## Background location

The app records rides with the screen off, so both stores treat it as a
background-location app.

- [ ] **(iOS)** `NSLocationWhenInUseUsageDescription` is set and says the app
      records rides while they are in progress.
- [ ] **(iOS)** `NSLocationAlwaysAndWhenInUseUsageDescription` is set if the
      significant-location-change relaunch stretch goal ships; otherwise it is
      deliberately absent.
- [ ] **(iOS)** `UIBackgroundModes` contains `location`.
- [ ] **(iOS)** `pausesLocationUpdatesAutomatically = false` and the background
      location indicator is enabled.
- [ ] **(iOS)** `PrivacyInfo.xcprivacy` is present and lists the required-reason
      APIs actually used.
- [ ] **(Play)** `android:foregroundServiceType="location"` is declared on the
      recording service and the `FOREGROUND_SERVICE_LOCATION` permission is in
      the manifest.
- [ ] **(Play)** Confirm the manifest does **not** request
      `ACCESS_BACKGROUND_LOCATION` (the service starts in the foreground; this
      avoids the stricter review). If it ever does:
  - [ ] the Play background-location declaration form is filled in,
  - [ ] a demo video showing the in-app feature and the runtime prompt is
        uploaded,
  - [ ] the prominent in-app disclosure is shown **before** the runtime
        permission prompt.
- [ ] **(Play)** A prominent in-app disclosure explains recording before the
      first location prompt, regardless of which permissions are requested.
- [ ] **(Play)** The "Minimum Scope" location declaration is submitted before
      November 2026 (enforcement starts January 2027).
- [ ] The notification shown during recording states what is happening and
      shows distance and time.
- [ ] The battery-optimisation exemption prompt is shown at most once and the
      app works if it is declined.

## Privacy labels and data safety

What leaves the device: routing waypoints, search queries, map tile requests,
the AI prompt with a coarse start position, the RevenueCat anonymous app user
id and purchase receipts, and — only on user action — rides and routes to
Strava or RideWithGPS, and shared routes to our share store.

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

## Privacy policy

- [ ] A public privacy policy URL is live and linked from both store listings
      and from the app's Settings → About.
- [ ] It names the AI provider, Strava, RideWithGPS, RevenueCat, the map tile
      provider and the search provider.
- [ ] It states retention for share links (one year) and that uninstalling
      removes local data.
- [ ] It has been reviewed by a lawyer (`docs/PRIVACY.md` is a draft).
- [ ] The crash-reporting section is resolved rather than "to be decided".

## AI features

- [ ] A one-time consent screen appears before any prompt leaves the device
      (Apple 5.1.2(i)), storing `denied`, `textOnly` or `withLocation`.
- [ ] Consent is revocable in Settings and revoking it disables the assistant.
- [ ] The start position sent with a prompt is rounded to about 1 km and no
      identifiers are in the prompt.
- [ ] A "report AI output" action exists (mailto or a GitHub issue template)
      and is reachable from the assistant sheet.
- [ ] The assistant's scope is constrained to route planning, and the
      age-rating questionnaire answers reflect that.
- [ ] The description step can be turned off by the user.
- [ ] AI descriptions are disabled for routes with `source == strava` (Strava's
      terms forbid AI use of their data).

## Purchases

- [ ] A **Restore purchases** button is on the paywall and in Settings, and
      works without any login.
- [ ] Price, billing period, renewal terms and trial length are shown on the
      paywall before purchase.
- [ ] Links to the terms of use and the privacy policy are on the paywall.
- [ ] The 7-day free trial is configured in both stores and in RevenueCat.
- [ ] Sandbox purchase, renewal, cancellation and restore-after-reinstall are
      all tested on both platforms.
- [ ] Every gated feature unlocks through in-app purchase only; there is no
      external payment link.
- [ ] A lapsed subscription hides the integrations and keeps all user data.

## Age rating

- [ ] The App Store age-rating questionnaire is completed, including the
      questions about AI assistants and user-generated content.
- [ ] The Play content-rating questionnaire (IARC) is completed.
- [ ] Expected outcome is 4+ / Everyone; if the answers push it higher,
      re-check the assistant's constraints before accepting the rating.

## Attribution and licences

- [ ] "© OpenStreetMap contributors" is visible in a corner of the map on every
      map screen.
- [ ] The About screen credits BRouter, Photon and OpenFreeMap (and CyclOSM
      when the overlay is enabled).
- [ ] An open-source licences screen lists all bundled dependencies and their
      licences.
- [ ] The CyclOSM overlay respects the OSMF tile policy: no bulk download, no
      pre-caching of raster tiles.
- [ ] `brouter/profiles` keeps BRouter's MIT header.

## Strava brand and API rules

- [ ] The connect button is Strava's official **"Connect with Strava"** asset,
      unmodified.
- [ ] The **"Powered by Strava"** logo appears wherever Strava data is shown.
- [ ] The word "Strava" does not appear in the app name, the store title or the
      icon.
- [ ] Every view of a Strava activity links back to that activity on Strava.
- [ ] Strava data is shown only to the athlete it belongs to.
- [ ] Cached Strava data is evicted after 7 days (`external_fetched_at`).
- [ ] Strava data is never sent to the AI provider.
- [ ] The Strava API review is submitted before the app exceeds 10 connected
      athletes (self-service works up to 10).
- [ ] The developer account holds an active Strava subscription, as their
      API terms require.
- [ ] The base URL move to `api-v3.strava.com` on 2027-01-04 is scheduled.
- [ ] The UI states clearly that a route cannot be created in Strava through
      the API, and offers "export GPX, then share" instead.

## RideWithGPS

- [ ] An API key has been requested and granted through their form.
- [ ] The OAuth redirect URI is registered and matches the app's scheme.
- [ ] Their branding and attribution requirements have been reviewed and
      followed.

## Accounts and store administration

- [ ] Check whether the Orkitec Google Play developer account is **personal** or
      **organisation**: a personal account requires a 14-day closed test with at
      least 12 testers before production access. Plan the timeline accordingly.
- [ ] App signing is configured (Play App Signing; iOS signing via fastlane
      `match`).
- [ ] Store listings, screenshots and icons are ready for both platforms.
- [ ] Export compliance: the app uses only standard HTTPS/TLS, so the exemption
      applies. Set `ITSAppUsesNonExemptEncryption = false` in `Info.plist` and
      answer the Play export declaration accordingly.

## App Review notes

Write review notes covering:

- [ ] Why background location is needed (recording a ride with the screen off)
      and how to reproduce it.
- [ ] That there are no accounts, so no demo credentials are needed.
- [ ] How to reach the AI assistant and that it is behind a subscription, with
      a sandbox/promo note on how the reviewer can try it.
- [ ] Where the privacy policy and the AI consent screen are.
- [ ] That map data is OpenStreetMap and routing is self-hosted BRouter.
