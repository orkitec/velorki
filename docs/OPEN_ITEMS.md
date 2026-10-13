# Open items

Everything below needs a person, a Mac, a live service, or a longer test on
the phone than has happened so far. The app runs on a Pixel 3 XL and has
recorded real rides; planning, on-device routing, the map and recording are
exercised there. The items here are the parts not yet covered by that.
iOS 1.0 is on the App Store; Google Play is at internal testing.

## Servers and accounts (Steffen)

- [ ] **Measure the battery saver**: everything [BATTERY.md](BATTERY.md)
      describes is in the app; the two comparison rides that would prove it are
      not. That file's "How to measure" is the procedure; write both numbers
      into it.
- [ ] **Strava**: submit the API review before 10 athletes connect; keep the
      developer account's Strava subscription active; move to
      `api-v3.strava.com` before 2027-01-04.
- [ ] **Head-unit sync** (Plus): send a route to Garmin, Wahoo and Hammerhead.
      None takes courses over Bluetooth from a third party; each has a cloud
      API behind a partner programme (Garmin Courses via Connect, Wahoo Cloud
      API, Hammerhead dashboard) that needs a server-side secret, so it lives
      in the relay. Garmin first. GPX export into the makers' apps works today.
- [ ] **Privacy policy, kept true**: the AI section says requests go through
      OpenRouter only to providers that neither train on nor retain them (keep
      those account settings on), and the log retention says 14 days for the
      web server's access logs and 90 for the application log lines in Orkify.
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

## Weather

- [ ] **Clouds, Europe against the US**: the Meteosat infrared images draw the
      same cold far darker than the GOES ones, so the same cloud is fainter
      over Europe. A per-source luminance window matched over the Atlantic
      overlap (Meteosat about 30–128 for GOES's 110–220) is set aside until
      screenshots of both show which way it should go.
- [ ] **OPERA radar**: the edge of its coverage leaves a pale wedge of
      satellite estimate west of Ireland. A MeteoGate API key
      (devportal.meteogate.eu) as a relay secret once the open bucket is not
      enough; the anonymous API is rate-limited.
- [ ] **More radar countries for Plus**: Austria from GeoSphere's 1 km
      nowcast (CC BY 4.0, 240 requests an hour); Latvia, the Balkans and
      Greece's gaps not yet looked into.
- [ ] **Plus forecast maps**: 2 km regional models for 2–60 h — DMI's
      HARMONIE DINI over most of Europe (CC BY 4.0, simple-packed GRIB2 from
      its EDR API) and DWD's ICON-D2 over central Europe — and the chance of
      rain as a map (DINI's ensemble percentiles, NOAA's NBM in the US).
- [ ] **WeatherKit** for the Plus route forecast worldwide, minute by minute
      for the first hour; Apple's terms on caching and attribution first.

## On the Mac (Xcode)

- [ ] **Apple Watch app** (`app/ios/VelorkiWatch`): no complications. A ride on the
      Series 6 with the phone locked is the real check: pulse arriving, wrist
      taps on time, watch battery after a ride. A paused ride ends the watch's
      session at every standstill, auto-pause included, and the first reading
      after a resume takes a few seconds; a minimum pause length before the
      sensor rests is the likely refinement. Still to be seen on the device:
      the "Ride started from your watch" notification, the pause behaviour,
      the sensor tile that stays with a broken-link mark, the average heart
      rate under it, and the elevation profile view (checked on the simulator
      and in a rendered widget test only).
- [ ] **Bluetooth on the Android phone**: scan, pair and ride with a strap or a
      cadence sensor on the Pixel; the manifest's `neverForLocation` scan flag
      and the capped legacy permissions were written without an Android SDK
      on the Mac. A combined speed-and-cadence sensor is stored with both
      kinds, so the wheel field shows for a crank-only one; reading the CSC
      Feature characteristic (0x2A5C) at pairing would settle it.
- [ ] `watch_connectivity` pulls `play-services-wearable` into the APK for an
      iOS-only feature; replace it with a small iOS-only channel if an F-Droid
      listing is wanted.
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

- [ ] **Store texts**: the free and Plus sections of the store descriptions
      say nothing of the weather yet; the French iOS description is 5
      characters short of Apple's 4000, so something has to go there.

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
