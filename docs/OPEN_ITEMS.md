# Open items

Everything below needs a person, a real device, a Mac, or a live service.
The code paths exist and are unit-tested; these are the parts that could not
be exercised on the Linux build machine. Ordered by what unblocks the most.

## Servers and accounts (Steffen)

- [ ] **Relay on the VPS with Orkify**: `api/` (`npm run build`, `node dist/server.js`, health `/health`, Node ≥ 22.13). Fill `.env` from `api/.env.example`. `SHARE_DB_PATH` must be on a persistent volume or every deploy invalidates share links. `OAUTH_REDIRECT_ALLOWLIST` must contain `velorki://oauth/strava,velorki://oauth/rwgps` verbatim.
- [ ] **BRouter on the VPS**: `deploy/` (compose with Caddy + BRouter + updater, or the systemd units). First planet sync takes 1–3 h; `SEGMENT_FILTER` for a regional start. Point `VELORKI_BROUTER_URL` at it (through Caddy: `https://api.velorki.app/brouter`).
- [ ] **rd5 mirror for on-device routing**: expose the updater's `/segments4` (with `manifest.json`) under `VELORKI_SEGMENTS_URL`. The app side is wired (Settings → Advanced → Offline routing data); with the variable empty it falls back to the brouter.de directory listing, which is a development fallback, not a server to ship against.
- [ ] **Strava API application**: client id/secret into the relay; "Authorization Callback Domain" = `oauth`; the developer account needs an active Strava subscription (Standard tier); self-service up to 10 athletes, then the review form.
- [ ] **RideWithGPS API client**: self-service key + OAuth client id/secret into the relay.
- [ ] **RevenueCat project**: entitlement `plus`, one offering with monthly/yearly packages, 7-day introductory offer on the store products; public SDK keys into `app/env/prod.json` (`VELORKI_REVENUECAT_KEY_ANDROID/IOS`), secret REST key into the relay (`REVENUECAT_SECRET_KEY`, `REVENUECAT_MODE=live`). Until then the relay can run with `REVENUECAT_MODE=stub`.
- [ ] **LLM**: `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL` in the relay (OpenAI now; any OpenAI-compatible endpoint later); set `LLM_DAILY_BUDGET_USD` and the per-1k prices.
- [ ] **velorki.app**: DNS for `api.velorki.app`; pages at `https://velorki.app/privacy` and `/terms` (docs/PRIVACY.md is the draft; a lawyer should read it); `support@velorki.app` and `security@orkitec.com` mailboxes (referenced in the app and SECURITY.md).
- [ ] **GL Strings**: `APPLANGA_ACCESS_TOKEN` secret in the GitHub repo; project configured for `app/lib/l10n/app_en.arb` (`.applanga.json`).
- [ ] **GitHub secrets for release.yml**: `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `APP_ENV_PROD_JSON`, `PLAY_SERVICE_ACCOUNT_JSON`.
- [ ] Photon: the app uses the public `photon.komoot.io` (fair use). Self-host when usage grows.

## On the Mac (Xcode)

- [ ] First iOS build: `flutter build ios`, provisioning, `fastlane/` setup (match repo, App Store Connect API key). `ios/Runner/AppDelegate.swift` gained an `application(_:open:options:)` handler for file opens that has never been compiled.
- [ ] Add the **Share Extension** target for `receive_sharing_intent` (share sheet on iOS); "Open in Velorki" already works without it. See `app/lib/features/import_export/README.md`.
- [ ] Exclude `<appSupport>/brouter/segments` from the iOS backup (`NSURLIsExcludedFromBackupKey`, a few lines in `AppDelegate.swift`): rd5 tiles are 125–250 MB each and are re-downloadable.
- [ ] Verify `LSApplicationQueriesSchemes` contains `strava` (M7) so the app-to-app OAuth flow is used when the Strava app is installed.
- [ ] Background recording on an iPhone: screen off for a long ride, the blue indicator, force-quit → interrupted-ride dialog on relaunch.

## On a real Android phone

- [ ] Recording: 2 h with the screen off, no gaps; swipe the app away mid-ride and reopen (reattach); kill the process and relaunch (resume/finish dialog restores the points); the notification updates and returns to the app on tap; battery-optimisation prompt appears once.
- [ ] Open-with: a GPX from a file manager, from Gmail, and from Chrome's download; a share-sheet GPX from Komoot. (The emulator cannot grant content URIs from the shell, so this was not automated.)
- [ ] OAuth callback lands in `CallbackActivity` without a chooser dialog (manifest hosts `oauth` vs `share`/`s`).
- [ ] Strava upload timing against the 2/4/8/16 s poll and `sport_type` acceptance; RWGPS task errors for an untimed GPX (`time_data_missing`).
- [ ] Sandbox purchase, restore after reinstall, the store subscription-management page.
- [ ] `velorki://share/<id>` from a browser opens the import preview.

## Store consoles

- Everything in `docs/STORE_CHECKLIST.md` that is still unticked: Play data safety + foreground-service declarations (with the demo video), App Store privacy answers, age rating, screenshots, the Play developer account type (personal accounts need a 14-day closed test with 12 testers).

## Later

- **Tile downloads in the background**: the rd5 download runs while the app is open and stops when it is killed (the `.part` file resumes on the next attempt). An Android `dataSync` foreground service with a progress notification, and iOS background URLSession, are the next step for 250 MB tiles.
- **Wi-Fi-only downloads**: `connectivity_plus` is not a dependency, so the app cannot tell Wi-Fi from mobile data; the download screen says so instead of offering a switch that would not work. Add the package, then a "Wi-Fi only" preference next to the routing preference.
- **rd5 format-version check**: every downloaded tile records the mirror's `formatVersion`, but `CompositeRoutingBackend.requiredFormatVersion` is left unset because nothing in the app knows which rd5 version this build of `brouter_dart` reads. Switch it on in R5, when the engine reports its own.
- On-device routing: R5 performance work is done (about half the JVM's speed, heap 65-77 MB); remaining are a measurement on a mid-range phone (target: a 60 km route under 3 s), rd5 delta updates, excluding the segments directory from iOS backup, and the format-version check below.
- The tile grid overlay on the map (the plan's third download entry point); the viewport and the planner's missing-tiles banner are wired.
- Photon self-hosting; rd5 delta updates (`Rd5DiffTool` stub); cloud sync.
