# Open items

Everything below needs a person, a Mac, a live service, or a longer test on
the phone than has happened so far. The app runs on a Pixel 3 XL and has
recorded real rides; planning, on-device routing, the map and recording are
exercised there. The items here are the parts not yet covered by that.

## Servers and accounts (Steffen)

- [ ] **rd5 tile mirror**: the app routes on the device, but `VELORKI_SEGMENTS_URL`
      has to point somewhere real. Either the VPS updater's `/segments4` or the
      GitHub Releases mirror in [orkitec/velorki-data][data]. A release holds at
      most 1,000 assets and the planet is 1,142 tiles, so a full snapshot is
      sharded (`tiles-YYYYMMDD`, `-s2`, …) with a per-shard `manifest.json`;
      until the app merges shard manifests, one URL covers one shard (Europe
      fits in shard 1). `app/env/dev.json` still points at `api.velorki.app`.
- [ ] **Relay on the VPS with Orkify**: `api/` (`npm run build`,
      `node dist/server.js`, health `/health`, Node ≥ 22.13). Fill `.env` from
      `api/.env.example`; `SHARE_DB_PATH` must be on a persistent volume.
- [ ] **BRouter on the VPS**: `deploy/` (compose with Caddy + BRouter + updater,
      or the systemd units). First planet sync 1–3 h; `SEGMENT_FILTER` for a
      regional start. Only needed for routing outside downloaded tiles.
- [ ] **Battery saver while recording**: nothing from [BATTERY.md](BATTERY.md)
      is implemented. Measure a baseline ride first, then stop sampling GPS
      twice (`devicePositionProvider` still runs alongside the recorder), a
      coarser GPS profile, dim/dark/black-map mode, and one "Battery saver"
      switch on the record sheet.
- [ ] **Strava API application**: client id/secret into the relay;
      "Authorization Callback Domain" = `oauth`; the developer account needs an
      active Strava subscription; self-service up to 10 athletes, then review.
- [ ] **RideWithGPS API client**: self-service key + OAuth client id/secret.
- [ ] **RevenueCat project**: entitlement `plus`, one offering with
      monthly/yearly packages, a 7-day introductory offer; public SDK keys into
      a `prod` env file (not committed), secret REST key into the relay
      (`REVENUECAT_SECRET_KEY`; `REVENUECAT_MODE` defaults to `live`, so set
      `stub` explicitly until then).
- [ ] **LLM**: `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL`,
      `LLM_DAILY_BUDGET_USD` in the relay.
- [ ] **velorki.app**: DNS for `api.velorki.app`; pages at `/privacy` and
      `/terms` (`docs/PRIVACY.md` is the draft; a lawyer should read it);
      `support@velorki.app` and `security@orkitec.com` mailboxes.
- [ ] **GL Strings**: `APPLANGA_ACCESS_TOKEN` secret in the GitHub repo.
- [ ] **GitHub secrets for release.yml**: `ANDROID_KEYSTORE_B64`,
      `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `APP_ENV_PROD_JSON`,
      `PLAY_SERVICE_ACCOUNT_JSON`.
- [ ] Photon: the app uses the public `photon.komoot.io` (fair use). Self-host
      when usage grows.

[data]: https://github.com/orkitec/velorki-data

## On the Mac (Xcode)

- [ ] First iOS build: `flutter build ios`, provisioning, fastlane (match repo,
      App Store Connect API key). `ios/Runner/AppDelegate.swift` has an
      `application(_:open:options:)` handler for file opens that has never been
      compiled.
- [ ] Add the **Share Extension** target for `receive_sharing_intent`; "Open in
      Velorki" already works without it. See
      `app/lib/features/import_export/README.md`.
- [ ] Exclude `<appSupport>/brouter/segments` from the iOS backup
      (`NSURLIsExcludedFromBackupKey`; the TODO is in
      `app/lib/features/routing_tiles/data/brouter_storage.dart`).
- [ ] Background recording on an iPhone: screen off for a long ride, the blue
      indicator, force-quit → interrupted-ride dialog on relaunch.

## Still to try on the Android phone

Done on the Pixel: planning with on-device routing, tile download over the
GitHub Releases mirror, recording a ride with the screen on, continuing a
stopped ride, the Library's rides list.

- [ ] Recording: 2 h with the screen off, no gaps; swipe the app away mid-ride
      and reopen (reattach); kill the process and relaunch (resume/finish
      restores the points); the notification updates and returns to the app on
      tap; the battery-optimisation prompt appears once.
- [ ] Open-with: a GPX from a file manager, from Gmail, and from Chrome's
      downloads; a share-sheet GPX from Komoot. (The emulator cannot grant
      content URIs from the shell.)
- [ ] OAuth callback lands in `CallbackActivity` without a chooser dialog.
- [ ] Strava upload timing against the poll backoff and `sport_type`
      acceptance; RWGPS task errors for an untimed GPX (`time_data_missing`).
- [ ] `LSApplicationQueriesSchemes` actually takes the app-to-app Strava flow.
- [ ] Sandbox purchase, restore after reinstall, a lapsed subscription, the
      store subscription-management page.
- [ ] `velorki://share/<id>` from a browser opens the import preview.

## Store consoles

Everything still unticked in [STORE_CHECKLIST.md](STORE_CHECKLIST.md).

## Later

- **Tile downloads in the background**: the rd5 download runs while the app is
  open and stops when it is killed (the `.part` file resumes next time). An
  Android `dataSync` foreground service with a progress notification, and iOS
  background URLSession, are the next step for 250 MB tiles.
- **Wi-Fi-only downloads**: `connectivity_plus` is not a dependency, so the app
  cannot tell Wi-Fi from mobile data; the download screen says so instead of
  offering a switch that would not work.
- **rd5 format-version check**: every downloaded tile records the mirror's
  `formatVersion`, but `CompositeRoutingBackend.requiredFormatVersion` is left
  unset because nothing in the app knows which rd5 version this build of
  `brouter_dart` reads. Switch it on when the engine reports its own.
- **On-device routing performance**: about half the JVM's speed, heap 65–77 MB.
  Still to do: a measurement on a mid-range phone (target: 60 km under 3 s) and
  rd5 delta updates (`Rd5DiffTool` is a stub).
- The tile grid overlay on the map; the viewport and the planner's
  missing-tiles banner are already wired.
- Photon self-hosting; cloud sync.
