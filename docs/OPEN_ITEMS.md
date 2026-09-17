# Open items

Everything below needs a person, a Mac, a live service, or a longer test on
the phone than has happened so far. The app runs on a Pixel 3 XL and has
recorded real rides; planning, on-device routing, the map and recording are
exercised there. The items here are the parts not yet covered by that.

## Servers and accounts (Steffen)

- [ ] **Web + relay on the VPS**: follow [docs/DEPLOY_WEB.md](DEPLOY_WEB.md) —
      Ubuntu 24.04, Node 22, Orkify, Caddy with a Cloudflare Origin CA
      certificate, the Cloudflare zone on Full (strict), backups. Then the
      `release`-environment secrets for `web-deploy.yml`: `DEPLOY_SSH_KEY`,
      `DEPLOY_HOST`, `DEPLOY_HOST_KEY`, `DEPLOY_USER`; and the process
      environment from `deploy/web/velorki-web.env.example` in the Orkify
      dashboard (`SHARE_DB_PATH` must stay outside the release tree).
- [ ] **BRouter on the VPS**: `deploy/` (compose with Caddy + BRouter + updater,
      or the systemd units). First planet sync 1–3 h; `SEGMENT_FILTER` for a
      regional start. Only needed for routing outside downloaded tiles.
- [ ] **Measure the battery saver**: everything [BATTERY.md](BATTERY.md)
      describes is in the app; the two comparison rides that would prove it are
      not. That file's "How to measure" is the procedure; write both numbers
      into it.
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
- [ ] **velorki.com**: the `support@velorki.com` and `security@orkitec.com`
      mailboxes. (Nameservers, DNS and TLS are step 5 of
      [DEPLOY_WEB.md](DEPLOY_WEB.md).)
- [ ] **Website legal pages**: fill the imprint placeholders in
      `web/content/en/legal/imprint.md`, set the effective dates in
      `privacy.md` and `terms.md`, have a lawyer read both.
- [ ] **Crowdin**: create the project (source English, target German), request
      the open-source plan, and add the `CROWDIN_PROJECT_ID` and
      `CROWDIN_PERSONAL_TOKEN` secrets in the GitHub repo.
      [docs/LOCALISATION.md](LOCALISATION.md) has the steps.
- [ ] **GitHub secrets for release.yml**: `ANDROID_KEYSTORE_B64`,
      `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `APP_ENV_PROD_JSON`,
      `PLAY_SERVICE_ACCOUNT_JSON`.
- [ ] **Geocoder**: the on-device gazetteer is done — a rider with routing
      tiles searches `<TILE>.gaz` first and only reaches Photon by tapping
      "Search online for …". The `publish-gazetteer` workflow in
      [velorki-data][data] builds them per Geofabrik extract after every
      tile snapshot. Remaining: a relay endpoint in front of Photon (Komoot
      first, a keyed OSM geocoder such as Geoapify as fallback) for everyone
      without tiles — the app goes straight to the public Photon instance
      today.
      Decided 2026-09-16: Apple and Google search are not options — Apple's
      agreement (Attachment 6, "Map Data" includes coordinates and points of
      interest; 2.4 results only on an Apple map; 2.5 not stored) and Google's
      terms (no Core Services with a non-Google map) both forbid a search pin
      on our OpenStreetMap map.

[data]: https://github.com/orkitec/velorki-data

## On the Mac (Xcode)

- [ ] iOS release signing, once: follow [RELEASE_IOS.md](RELEASE_IOS.md) —
      the private `velorki-certs` repo, `fastlane ios certs` with
      `MATCH_READONLY=false`, the App Store Connect API key, the six GitHub
      secrets. The lanes (`app/fastlane/Fastfile`) and the tag workflow
      (`.github/workflows/ios-release.yml`) are written and wait on it.
      Development builds sign automatically with the orkitec team and run on
      a phone; the file-open handler in `ios/Runner/AppDelegate.swift` has
      not been tried yet.
- [ ] Sign once with the **Share Extension**: the `VelorkiShare` target exists
      and CI compiles it, but the App Group `group.com.orkitec.velorki` is only
      registered in the developer portal after one signed build on the Mac.
- [ ] Background recording on an iPhone: screen off for a long ride, the blue
      indicator, force-quit → interrupted-ride dialog on relaunch.
- [ ] **Associated Domains**, once: enable the capability for the app id in
      the developer portal (the `applinks:velorki.com` entitlement is already
      in `ios/Runner/Runner.entitlements`). The website must serve the two
      `.well-known` files for the links to verify, which needs `APPLE_TEAM_ID`
      and `ANDROID_CERT_SHA256` — the release keystore's SHA-256 fingerprint
      from `keytool -list -v` — in its environment.
- [ ] Voice cues over a Bluetooth headset: one ride with the headset paired,
      to confirm the held audio session and the silent lead-in really do stop
      cues arriving scrambled or cut short (`turn_speaker.dart`,
      `LeadInPlayer` in `ios/Runner/AppDelegate.swift`).

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
- [ ] Tap a `https://velorki.com/s/<id>` link in Chrome: the app opens
      directly (App Links verification), not the website.

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
- **On-device routing performance**: about half the JVM's speed, heap 65–77 MB.
  Still to do: a measurement on a mid-range phone (target: 60 km under 3 s) and
  rd5 delta updates (`Rd5DiffTool` is a stub).
- The tile grid overlay on the map; the viewport and the planner's
  missing-tiles banner are already wired.
- **Data hosting before launch**: the mirror is GitHub Releases, which has no
  service commitment and undocumented bandwidth limits. Decided 2026-09-16:
  move `latest.json` and the files to an S3-compatible object store with free
  egress (Cloudflare R2, or Hetzner Object Storage for a German provider),
  keep GitHub Releases as the fallback, and teach the app a list of mirrors
  in the pointer. Both publish workflows gain an upload step.
- Photon self-hosting; cloud sync.
