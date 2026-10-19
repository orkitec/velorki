# Architecture

What Velorki is made of. Toolchain and testing: [`app/README.md`](../app/README.md).
The relay's HTTP contract: [`web/openapi.yaml`](../web/openapi.yaml), described
in [`web/README.md`](../web/README.md).

## Systems and data flow

| System | Where it lives |
|---|---|
| Flutter app and its pure-Dart packages | this repo, `app/` — the only part that ships to a store |
| Web + relay | this repo, `web/` — one Next.js app, two hostnames: `velorki.com` (site, docs, legal, share pages) and `api.velorki.com` (the relay). Deployed by Orkify as a two-worker cluster behind Caddy and Cloudflare, see [DEPLOY_WEB.md](DEPLOY_WEB.md) |
| BRouter routing server and segment updater | this repo, `brouter/` + `deploy/` — optional, on a VPS |
| Gazetteer builder | this repo, `tools/gazetteer/` — Python, run by CI in the mirror repo |
| BRouter test oracle | this repo, `tools/brouter-oracle/` — parity runs only, never shipped |
| Tile and search mirror | `orkitec/velorki-data`, GitHub Releases (local checkout `~/Work/velorki-data`) |
| CI | GitHub Actions in both repositories |

Upstreams: brouter.de (rd5 tiles), Geofabrik (the OSM extracts the `.gaz` files
are built from), OpenFreeMap and CyclOSM (map tiles), Photon (online search),
DWD, KNMI, FMI, NOAA, the Iowa Environmental Mesonet, NASA GIBS and EUMETSAT
(the free weather map: rain radar, H SAF satellite rain, ICON and HRRR
forecasts, clouds and ICON wind, and the free route weather from ICON, fetched
by the phone, no relay), EUMETNET OPERA and the Dipartimento della Protezione
Civile's Radar-DPC (the Plus rain radar across Europe and over Italy, drawn by
the relay from their open data), NWS, DWD MOSMIX via Bright Sky and
MET Norway (the Plus route forecast, through the relay).

```
 brouter.de/segments4                      Geofabrik extracts
        |                                         |
        | publish-tiles                           | publish-gazetteer
        | (1st of the month, 03:00 UTC)           | (after publish-tiles)
        v                                         v
  +-----------------------------------------------------------+
  | orkitec/velorki-data - GitHub Releases                    |
  | tiles-YYYYMMDD (+ -s2, -s3): <= 480 tiles a shard,        |
  |   <TILE>.rd5 + <TILE>.gaz + manifest.json per release     |
  | main/latest.json: the pointer - formatVersion, shards[]   |
  +-----------------------------------------------------------+
        ^  1. VELORKI_SEGMENTS_URL is that latest.json
        |  2. every shard's manifest.json, merged into one
        |  3. <TILE>.rd5 (resumable), and <TILE>.gaz where the
        |     tile entry carries a `gazetteer` object
  +-----------------------------------------------------------+
  | Phone: brouter_dart routes on the rd5, GazetteerStore     |
  | searches the .gaz - both with no network                  |
  +-----------------------------------------------------------+
     |             |                  |               |
 OpenFreeMap,   Photon            BRouter server    Relay (web/)
 CyclOSM        online search,    (optional):       OAuth exchange,
 map tiles      no tiles needed   areas with no     LLM, share links,
                                  tiles             weather
```
File format and builder: [`tools/gazetteer/README.md`](../tools/gazetteer/README.md).
Mirror layout, sharding, `latest.json` and the resume path:
[velorki-data's README](https://github.com/orkitec/velorki-data#readme).

## The guiding rule

**As much as possible runs on the device.**

The phone holds the routes, the rides, the loop generator, file import and
export, and the routing itself. The server side exists only for what an
open-source app cannot do: a BRouter server as an alternative to downloading rd5
tiles, the OAuth client secrets and the model API key, the hosted model behind
them, and the store for share links. No accounts, no cloud database, no sync
server: sync goes to the rider's own iCloud or Google Drive.

## Components

**No backend is required to run Velorki.** With `VELORKI_BROUTER_URL` and
`VELORKI_API_URL` empty the app routes on the device from downloaded rd5 tiles
and hides the Plus features — see [SELF_HOSTING.md](SELF_HOSTING.md).

```
  Phone (Flutter app) ──► OpenFreeMap, CyclOSM, Photon, the rd5 segment mirror
   routes, rides, loops,    tiles, search, routing-tile downloads
   GPX/FIT, recording,  ──► BRouter server (optional) — routes for areas with
   brouter_dart on rd5      no downloaded tiles
                        ──► Relay (web/, Node 22, no accounts, no user DB)
                              ├─ OAuth code → token (secrets added) → Strava,
                              │  RideWithGPS; tokens handed back wrapped, and
                              │  every service call passes through /proxy/*
                              │  (free: unwrap, forward, keep nothing)
                              ├─ AI: prompt → an OpenAI-compatible LLM provider
                              └─ share links
```

## App architecture decisions

| Topic | Choice | Why |
|---|---|---|
| State and DI | Riverpod 3 with `riverpod_annotation` codegen, no `get_it` | doubles as dependency injection; testable through `ProviderContainer(overrides:)` |
| Persistence | Drift 2 (SQLite) for routes, rides, offline regions and tiles; `shared_preferences` for settings; `flutter_secure_storage` for OAuth tokens | typed SQL, migrations, streams |
| Geometry storage | one packed `BLOB` per route or ride (`velorki_geo/PackedTrack` v2: lat f64, lon f64, ele f32, timeMs i64, speed f32, acc f32, heart rate u16, cadence u16, power u16 = 42 bytes per point, with a version byte; v1 records are the first 36 of those and still decode) | 10k points are one row of 420 KB instead of 10k rows; the same format is the recording journal |
| Navigation | go_router with `StatefulShellRoute` and four tabs (Plan, Record, Library, Settings); deep links through `app_links` | few routes, so no `go_router_builder` |
| Codegen | freezed, json_serializable, drift_dev, riverpod_generator, gen-l10n; generated files are not committed, `app/tool/gen.sh` runs them | |
| HTTP | dio | interceptors for token refresh, the rate-limit bucket, multipart, cancellation |
| Map | maplibre_gl behind a `MapController` interface so widget tests can fake it; style URL from config | BSD-licensed, vector tiles, offline regions. Mapbox is proprietary and metered per monthly active user |
| Map tiles | OpenFreeMap vector tiles by default; an offline cycle map drawn from the rd5 tiles, or CyclOSM raster as an online overlay | no key, no limits; swappable to self-hosted PMTiles |
| Weather map | rain from a ranked list of sources, picked per time-control step (now, quarter hours to +2 h, hours to +24 h) by `rainPartsAt`: radar (DWD, KNMI and FMI WMS, NOAA ImageServer) and the DWD nowcast where they reach, with Velorki Plus the DPC's rainfall over Italy and then the EUMETNET OPERA composite after the free radars (one image of the view from the relay, which fetches each five-minute GeoTIFF from its publisher once, keeps it as a grid of DWD classes in the cluster's shared cache and draws it in the DWD radar's colours and grey, the DPC's apart from any other source as its CC BY-SA asks; the only weather requests that carry the relay's credentials, so drawn as an image in either look), H SAF satellite rain (EUMETSAT WMS) around them at "Now", ICON-EU (hourly, in the DWD radar's style), HRRR over the contiguous US (IEM's reflectivity tiles every 15 minutes of the newest run its `refd_0000.json` names, put together on the phone into one image of the view, at most 16 tiles) and global ICON (six-hour sums) ahead, forecasts as opaque as measurements; each source masked on the phone by those before it: drawn soft, by where the DWD's or the HRRR's frame of the same step measures (read from that image: not its grey "no data", inside its grid), crossfaded over 25 km inside that edge, else by their fixed reach or coverage. Soft by default: one image of the view and its surroundings per source at its native resolution, fetched when the camera rests, each pixel read against the service's legend (hard-coded per source in `rain_legend.dart`; anything not in it, such as the DWD's reach line, dropped), its alpha by the class's rank and its edges blurred in an isolate, drawn as an image source with linear resampling; "As measured" in Settings → Appearance keeps the radars' raster tiles and draws satellite and model images as they come, masked only; clouds as one image per region (EUMETSAT and NASA GIBS WMS), and from zoom 6 a second image of the view and its surroundings at the service's native resolution over it, fetched when the camera rests, both whitened by brightness on the phone and drawn as image sources with linear resampling; wind as one plain-text grid of the view and a quarter around it per time-control hour (global ICON 10 m u/v, DWD WCS `GetCoverage` `format=text/plain`, thinned by the service's `scalesize` when zoomed out; a box across the antimeridian is one request, the service wraps), cached for an hour, from zoom 3, turned on the phone into our own arrows: points on a world-fixed ~70 px grid, bilinearly interpolated, a GeoJSON symbol layer of one SDF arrow coloured and sized by speed over the rain and clouds; `WeatherMapDriver` picks the sources over the view and refreshes them | free public services; EUMETSAT's Meteosat images only on the full hour, which its data policy makes free; SAF products are Core data at any latency |

Versions live in `app/pubspec.yaml`. Deliberately not used: `strava_client` (it
expects the client secret inside the app) and `latlong2`.

## Layout

One monorepo — a Dart pub workspace in the root `pubspec.yaml`, no melos — so
app, site and relay change in the same commit and a fork can self-host from a
single clone: `app/` the Flutter app and its pure-Dart `packages/`, `web/` the
website and the relay in one Next.js app, `brouter/` the `.brf` profiles and
the rd5 updater image, `deploy/` compose file, Caddy and systemd units,
`tools/` the oracle. All of it is AGPL-3.0-only.

Inside `app/lib` the layout is feature-first: one directory per feature under
`features/`, each with `data/`, `domain/`, `application/` and `presentation/`,
plus `core/`, `app/` and `l10n/`. Only `app_en.arb` is edited by hand; the other
ARB files come from Crowdin (`docs/LOCALISATION.md`).

### Look and feel (`app/lib/app/theme.dart`)

`buildLightTheme(preset)` / `buildDarkTheme(preset)` with five accent presets
(`AccentPreset`: volt, ember, glacier, berry, forest), chosen under Settings →
Appearance next to the light/dark/system switch (`AppearanceSetting`). Two
typefaces ship as assets: Barlow Condensed for headlines and figures, Manrope
for everything else. `VelorkiColors` (a `ThemeExtension`) carries what Material
has no slot for — route, track and marker colours, the glass panels over the
map, the semantic colours — and `MapPalette.fromTheme` turns it into the
maplibre layer colours, so the route follows the accent. Dark mode also swaps
the map style.

### Units (`app/lib/core/units/units.dart`)

`UnitSystem` is metric or imperial, and `formatDistance` / `formatSpeed` /
`formatElevation` convert a figure and say which unit it came out in; the
translated label goes round it in `route_format.dart`. The choice sits under
Settings → Appearance (`UnitsSetting` on `units.system`, nothing stored until
the rider picks a side, defaulting to imperial only where the phone's country
does — US, LR, MM). Every stat tile, slider, chart axis, turn banner and
spoken cue reads it from `unitSystemProvider`.

### Pure-Dart packages (`app/packages/`)

None depend on Flutter, so they run and are tested on the desktop Dart VM.

| Package | Owns |
|---|---|
| `velorki_geo` | `LatLng`, distance, bearing, bounding boxes, the packed geometry codec |
| `velorki_gpx` | GPX reading and writing |
| `velorki_fit` | FIT activities and courses |
| `velorki_brouter` | the `RoutingBackend` interface, the HTTP, local and composite backends, and the GeoJSON/`messages` parser producing `RouteResult` |
| `velorki_loops` | the loop candidate strategies and the scorer |
| `velorki_cycle_map` | the offline cycle map: ways classified from the rd5 tiles, cached per cell, written as GeoJSON in an isolate |
| `velorki_api` | the client for the relay |
| `brouter_dart` | the Dart port of the BRouter routing runtime |
| `velorki_io` | `dart:io` on the phone, an in-memory stand-in for its files in the browser |

`RoutingBackend` is the seam that keeps the planner free of where a route comes
from: it only ever calls `route()`.

### The web planner (`flutter build web --wasm`)

The same app, compiled to WebAssembly (64-bit ints for the routing engine), as
the planner and the library on app.velorki.com. `main.dart` picks
`lib/app/web/bootstrap_web.dart`; where the phone and the browser differ, a
conditional import (`if (dart.library.js_interop)`) picks the implementation:
files (`velorki_io`, kept across visits in Cache Storage by `WebFileStore`),
the database (drift's WebAssembly SQLite in a worker, `connection_web.dart`),
the gazetteer's SQLite (`gazetteer_sqlite_web.dart`), the app's directories
and the routing worker (on the page's event loop: a browser has no isolates).
`platformFeaturesProvider` is what screens ask before offering what a browser
cannot do (recording and navigation, store purchases, Strava and Ride with
GPS, offline map packs, the routing server: the browser routes on its own,
and the tiles a route needs are fetched as soon as it needs them,
`MissingTilesBanner`). Tiles come from the Pages Function under `/tiles/`
(`deploy/cloudflare/`), so the mirror needs no CORS. `tool/web_assets.sh`
fetches `sqlite3.wasm`, `drift_worker.js` and maplibre-gl-js before a build
(`--no-web-resources-cdn`): the page's code comes from no CDN (only the
engine's fallback fonts do, from fonts.gstatic.com, and Google's or
Apple's sign-in script once the rider picks that sync), and
`web/_headers` holds the Content-Security-Policy naming every host it does
talk to. The isolate work (cycle map, weather images) runs inline through
`package:velorki_io/worker.dart`, zlib is package:archive's. Where the
maplibre web plugin differs from the phones, `PluginMapLibreStyleOps` makes
up for it (string feature ids as a promoted property, image sources over
blob: URLs), and the map, an HTML element under Flutter's canvas, only gets
the pointers Flutter's hit test gives it (`platform_view_pointer_gate.dart`).
`web/device_gate.mjs` keeps purchases_flutter's web SDK off the page.
The glass over the map (`GlassBackdrop`: the bar, the panels, the chips, the
docked pill) blurs the map with the browser's own `backdrop-filter`: boxes in
the glass's place inside each map's element (`web_glass_layer.dart`); where
the browser has none, the rider wants less transparency or it is too slow,
the glass is drawn as Subtle (`GlassBlur`).

## Data model

Drift owns five tables, schema version 11. Connected accounts live in secure
storage, not in the database.

- **`routes`** — id (uuid), name, description, `source`
  (`planned|loop|imported_gpx|imported_fit|strava|rwgps`), profile, timestamps,
  distance, ascent, descent, bbox, the geometry blob, and waypoints, routing
  options, surface stats, external ids and `external_fetched_at` as JSON.
- **`rides`** — id, name, start and end, distance, moving and elapsed time,
  ascent, descent, average and maximum speed, average and maximum heart rate,
  average cadence and average power (null without a sensor), an optional
  `route_id`, the geometry blob including time and the per-fix sensor values,
  pauses, uploads, notes.
- **`offline_regions`** — the downloaded MapLibre offline map regions.
- **`routing_tiles`** — the rd5 segment tiles downloaded for on-device routing:
  name, bytes, `updated_at`, `format_version`, state.
- **`sync_records`** — the sync outbox, one row per route and ride, written
  by SQLite triggers on `routes` and `rides` (`core/db/sync_triggers.dart`):
  last change time, a version, dirty and tombstone flags, the server's system
  fields (CloudKit's, or a store's version), a ride's route link still waiting for its route.

## Key flows

**Planner.** Ordered waypoints plus `RoutingOptions{profile, alternativeIdx}`;
edits are debounced 300 ms and then call `RoutingBackend.route()`. The
`RouteResult` carries the geometry, the ascent and BRouter's `messages` (way
tags per segment), from which the surface statistics are derived. Dragging the
line inserts a via point; alternatives 0–3 and an undo stack sit on top. The
map keeps its full size under the keyboard (neither scaffold resizes for it);
the plan sheet drops to its handle when the search field takes focus and comes
back when the keyboard goes.

**Import and export.** `IncomingFileService` unifies open-with (`app_links`,
`content://` URIs) and the share sheet (`receive_sharing_intent`). The file type
comes from sniffing the bytes — `<gpx` or `<?xml` versus the FIT header at
offset 8 — not the MIME type; timestamps decide route or ride. Both manifests
must declare the file types.

**Recording that survives an app kill.** The recorder appends 42-byte
`PackedTrack` records to `<appSupport>/recording/<rideId>.vtj`, flushing every
5 points or 10 seconds, next to a `recording_state.json`. On launch
`RecoveryService` reattaches to a running recording or offers Resume/Finish for
an orphaned one; finalising computes the statistics (moving time at 1 km/h,
ascent with 3 m hysteresis) and writes the `rides` row. On Android
the `flutter_foreground_task` isolate owns the geolocator stream, the journal
and the live statistics; the manifest deliberately does **not** request
`ACCESS_BACKGROUND_LOCATION`, because the service always starts in the
foreground, which avoids the stricter Play review. On iOS "When In Use" plus
`UIBackgroundModes location` suffices, and every consumer of fixes goes
through one `SharedPositionSource`: geolocator on iOS allows a single
position stream, and the recorder subscribes while the map's is still open,
so the source runs one platform stream with the strongest settings asked for
(the recorder's background-capable ones win) and fans the fixes out. While a ride runs the camera follows
the rider in one of two styles, north-up or heading-up (the map turned to the
smoothed course, as `HeadingSmoother` gives it); the locate button picks the
following up again, and the compass button below it swaps the style, its
needle turned to the map's bearing. The choice is kept in
`recording.follow`, so the next ride starts the way the last one was ridden,
and a pan or a twist of the map hands it back to the rider. While the rider is
within `routeSnapMeters` (30 m, or the fix's own accuracy when that is worse)
of the guided route the puck is drawn at `NavigationProgress.snapped`
and pointed along `routeBearingDeg`, so neither wanders with the fix; the
adapter then walks the puck to each new fix over 800 ms instead of hopping.
The camera glides over a one-second fix interval and is only turned when the
bearing has moved more than 8°, and never below 1.5 m/s, where a GNSS course
is noise. Standing still there is no course at all, so the heading then comes
from the phone's magnetometer instead (`compass_heading.dart`, tilt-compensated
against the accelerometer, `autoDispose` so it only runs on the Record tab),
which is what lets the cone and heading-up work at a red light. Only one GPS
client runs while a ride does: `devicePositionProvider`, the map's own stream,
ends itself for the duration. How hard that one client is driven is the GPS
precision setting, which travels to the service isolate inside
`recording_state.json`, and Settings → Recording → Battery saver trades the
screen for range: dark theme and black map through `appearanceOverrideProvider`
(an override, never a write to the rider's choice), a bare puck, no camera
animation, 40 % brightness while the screen is held awake, and a black glance
page of figures after 30 s without a touch. See [BATTERY.md](BATTERY.md).
A finished ride is measured a second time by `core/geo/ride_analysis.dart`
(`analyseRide`, once per ride and unit system through `rideAnalysisProvider`):
kilometre or mile splits, at most 400 smoothed chart samples for the elevation,
speed and heart rate charts, and the track cut into five speed classes by its
own quantiles, which the ride page draws through
`MapController.setTrackSegments`.

**Sensors.** `features/sensors` is one `SensorHub` (a keep-alive Riverpod
notifier) that every source registers with: heart rate, cadence, wheel speed
and power, each reading tagged with the source it came from. For every kind the
hub publishes the reading of the highest-priority source that has reported
inside 10 s — a watch (3) beats a Bluetooth sensor (2) beats a health store
(1) — and hands back to a lower one as soon as the higher falls silent, so a
strap left at home is simply not there. The hub is the only thing the recorder
talks to: `RecordingEngine` asks it once per fix and stamps the fresh values
onto the track point, and once per snapshot for what the sheet shows. On iOS
the engine reads the provider directly; on Android it lives in the service
isolate, so the main isolate pushes each change across the port with
`sendDataToTask`, at most once a second, and the task handler holds the last
one. The first source is the phone's own health store, Apple Health or Health
Connect behind one `HealthGateway`: with the switch in Settings → Sensors on
and a ride recording, `HealthSensorSource` polls it every 5 s (30 s in battery
saver) and turns each new sample into a reading. When the ride is saved,
`RideHealthSync` fills the fixes that carry no heart rate from that same store,
recomputes the statistics if it filled any, and writes the ride back as a
cycling workout — once per ride, and nothing at all while the switch is off.
The second source is the rider's Apple Watch, behind its own switch: the
watchOS app in `ios/VelorkiWatch` (embedded in Runner, see its README) runs a
workout session for the heart rate and shows what the phone reports, and
`WatchRideBridge` is the phone's end of it — the watch's readings go into the
hub, the lock screen's own formatted figures go out as the application context
at most every 5 s, and the buttons on the wrist call the recorder. The watch
never records: finishing from it stops the recorder and leaves the save sheet
for the next time the phone is looked at. The third source is Bluetooth Low
Energy, `BleGateway` over `universal_ble`, with the three cycling GATT
profiles parsed in pure Dart (`ble_profiles.dart`): heart rate, speed and
cadence — revolutions and event times differenced into a speed with the wheel
circumference setting behind them — and power, whose crank counters make a
cadence sensor unnecessary. It scans only when the rider taps Scan on
Settings → Sensors → Bluetooth sensors, which is also the only thing that can
raise the Bluetooth permission, and `BleSources` connects the paired devices
only while a ride records or that screen is open, reconnecting on a 1/2/5/10 s
backoff. A fresh wheel speed replaces the GPS speed on the record sheet, and
nothing else.


**Lock screen.** While a ride records, `RideNotificationUpdater` (kept alive
for the session and read once by `HomeShell`, like the navigator) writes what
the rider sees without unlocking the phone: on Android the second line of the
ongoing notification, on iOS a live activity, from one code path. With
guidance it reads `Turn left in 150 m · 3.2 km · 00:42`, `Off route · …` when
the rider has strayed, and the plain figures when no route is being followed.
The notification is written at most every 2 s and only when the line actually
changed; the live activity at most every 5 s. Both isolates could write that
line, so the main one takes it on a lease: every update tells the service
isolate through `sendDataToTask` to leave the text alone for the next 10 s,
and a UI that was destroyed simply stops renewing, at which point the service
goes back to writing its own distance and time. The iOS card is the
`live_activities` plugin plus the `VelorkiLiveActivity` widget extension target
— see `app/ios/VelorkiLiveActivity/README.md`.

**Turn-by-turn.** BRouter's voice hints travel with a route as `TurnHint`s and
are stored with it. While a ride runs, `NavigationController` (kept alive for
the session, read once by `HomeShell`) feeds every fix to `TurnNavigator`, which
matches the rider onto the followed route — the saved one, or the plan when none
was chosen — and reports the next turn, the one after it, the distance left and
whether the rider strayed. `TurnAnnouncer` turns that stream into cues given
once each; `TurnBanner` shows the current one over the map and `TurnSpeaker`
(`flutter_tts`) says it. Settings: `navigation.turns` shows the banner,
`navigation.voice` speaks it, `navigation.rerouteMode` (`RerouteMode`: guide
back, new route, off; the old `navigation.reroute` bool is read as guide back
or off) says what leaving the route does. The same settings are on the record
sheet, and the
banner carries a mute button that silences the voice for the rest of the ride
only (`voiceMutedForRideProvider`, cleared whenever a ride starts or ends).
On iOS the speaker holds one audio session for the whole spoken stretch rather
than the one per cue `flutter_tts` would otherwise take and give back, and each
cue is preceded by 1.5 s of silence (`assets/audio/silence.wav`, played by
`AppDelegate` over `app.velorki/audio`). Both are for Bluetooth headsets, whose
A2DP link goes idle between cues and takes about a second to come back — long
enough to swallow the first syllables of a turn.
A rider who leaves the route goes through `OffRouteMachine`: more than
`max(75 m, 2 × accuracy)` out for two fixes (or 8 s) is `guiding`, in every
mode — the plan stays the active route and the banner and the voice point at
the nearest route point still ahead, with a distance and a
left/right/ahead/behind from the bearing minus the rider's heading, no routing
at all, because most strays are a wrong turn undone within a block. Still off
45 s or 150 m later (never before 15 s), or on a tap, the mode decides.
`guideBack` routes a way back: candidates 300 m, 800 m and 2 km further along
the plan, counted from the rider's own place beside it (`rejoinFromM`), are
routed from the rider in that order (through a via point 40 m along their
heading above 1.5 m/s, BRouter having no heading parameter); the first that
rides no one-way the wrong way, no pavement and does not turn the rider round
(`route_check.dart`), and is at most 3× its beeline, wins. It is stitched to
the rest of the plan as one route in `detourRouteProvider`, drawn as a branch
beside the plan, and dropped silently within `max(30 m, accuracy)` of the plan.
A rider who rides away from it gets another only 300 m (straight line) from
where the last was worked out, and only if off it or past its target, never
aimed short of the last target; the plan is never replaced. `newRoute`
re-plans from the rider through the stops not yet reached, which replaces the
plan (the old one drawn faint), and again only 300 m from where it last did.
`off` routes nothing. Every distance scales with the fix's reported horizontal
accuracy, capped at 100 m so a phone that has lost the sky cannot switch
off-route detection off (`off_route_thresholds.dart`). "New route from here"
re-plans the whole ride on request in any mode.

**Integrations and OAuth.** One `OAuthFlow`: build the authorise URL, open it
with `flutter_web_auth_2`, receive the redirect on `velorki://oauth/<service>`,
exchange the code **through the relay**, store the tokens in secure storage
**as the relay wrapped them** (AES-GCM under a key only the relay has); a dio
interceptor refreshes 60 s before expiry. Every service call goes through the
relay's `/proxy/<service>/…` with the wrapped token in `X-Velorki-Token`: the
relay limits per IP and per install id (no subscription: Strava's API Policy
forbids charging for its functionality), unwraps in memory, forwards
with the service's bearer and streams the answer back, storing nothing; a
token under a retired key comes back re-wrapped and replaces the stored one.
Strava rides go up as multipart uploads, polled with backoff and then linked
to; the imported route list is
cached for 48 hours, a client-side bucket keeps reads under 90 per 15 minutes, and
AI descriptions are refused for `source == strava`. Strava's API cannot create
routes, so sending one *to* Strava is "export GPX, then share"; Komoot and
Garmin are file-based only.

**Sync.** Each device syncs with one cloud, Settings → Sync with: iCloud
(iOS 17 and later, the default there), Google (the Drive app data folder) or
off (the default everywhere else); the old iCloud switch maps on to iCloud.
Every service runs behind `SyncBackend` (`features/sync/data`), so
`LibrarySync`, `SettingsSync` and `RecordCodec` are the same over all of
them; switching service sends the library to the new one as new and deletes
nothing (`sync.records_service`). Clouds without a sync engine of their own
go through `StoreSyncBackend`, CKSyncEngine's part in Dart over a
`CloudStore` (batch push over each record's version, pull from a cursor,
full listing when it expires, account id): `sync_records` stays the outbox,
the version rides in `system_fields`, the cursor and account in the
preferences, transient failures back off with jitter.

**Google sync.** `DriveCloudStore` is the `CloudStore` over the Drive v3
app data folder (scope `drive.appdata` only). The layout, which the relay
and the web planner read too (`driveRecordFile`, `readDriveRecord`):

- One file per record in `appDataFolder`, its `name` the record name
  exactly, no extension: `route_<id>`, `ride_<id>`, `settings`,
  `plus_<deviceId>`.
- `appProperties`: `kind` (the record type: `Route`, `Ride`, `Settings`,
  `PlusDevice`), `modifiedAt` (ms since the epoch) and `codec` (the
  codec's schema version) where the record has them, all strings.
- A record of short text fields alone (each key and value at most 124
  bytes together, as `PlusDevice`) keeps them in `appProperties` too and
  has empty content.
- Any other record's content is one UTF-8 JSON line,
  `{"v":1,"type":…,"fields":{…},"body":true|false}`, a newline, and then
  the codec's gzip JSON body bytes unchanged (routes and rides; settings
  have no body). Fields keep their types there. `v` is the header's
  version: a reader skips a file whose `v` is newer than it knows.

A version is the file id and Drive's `version`; a save
over one reads the file first (one `files.list` per batch of names) and
compares, the race accepted; of two files with one name the older counts.
Changes come from `changes.list` (deleted files' ids resolved through a
map kept in the preferences), a refused page token lists the folder
again, 403 `storageQuotaExceeded` is quota, 429 and 5xx are transient.
Sign-in is `google_sign_in` behind `GoogleSignInService`: choosing Google
in Settings signs in and authorises the scope first; the account (id,
email) is kept in the preferences and is the store's account id. Tokens
come silently, once more after a 401; one only the rider can grant again
signs the account out. Sign out turns sync off and deletes nothing.
Offered on iOS (`GIDClientID` in Info.plist) and on Android when
`VELORKI_GOOGLE_WEB_CLIENT_ID` is set (Credential Manager's
`serverClientId`). Tests run over `FakeDrive`, Drive at the HTTP layer.

**iCloud sync.** `ios/Runner/CloudSync.swift` runs CKSyncEngine on the private
database's `Library` zone (container `iCloud.com.orkitec.velorki`) and keeps
its state in Application Support; the rows stay in Drift, so the engine asks
Dart for each record as it sends and hands every fetched change to Dart,
waiting for it to be written (`features/sync`, channel `velorki/cloud_sync`).
The engine fetches only what a push told it of; a manual fetch (launch,
switching sync on, the Library tab, a pull, a return to the app) asks for the
zone's changes itself, since its own change token beside the engine's state,
and the engine's later fetch of the same changes is dropped natively or is a
no-op in Dart.
The triggers mark every write, whatever path made it; the record format is
`RecordCodec` (versioned fields, the track and other large columns as one
gzip JSON asset). The newer change wins per record, the server's copy on a
tie; a delete from elsewhere loses to a local change not yet sent. Strava
routes and every upload link stay on the phone, partner ids too. Another
account, a sign-out or a reset zone resends the library as new and never
deletes it; data deleted from iCloud in Settings switches sync off. A few
settings (`syncedSettingKeys`) go through the iCloud key-value store.

**Sync in the browser.** The web planner offers iCloud and Google, both off
until chosen, each signed in from Settings → Sync with by the provider's own
button. Google is google_sign_in's web implementation (Google Identity
Services, `ButtonGoogleSignIn`): its script is held back by
`web/device_gate.mjs` until the rider picks Google; a token comes only from a
click and lasts an hour and no reload, so a missing one is
`CloudStoreFailure.signInNeeded` (the account stays, what waits stays queued,
the section says "Sign in" and asks Google's popup again), never a lost
account; `DriveCloudStore` is the phone's. iCloud is
`CloudKitJsCloudStore` over CloudKit JS (`CloudKitWeb`,
`cloudkit_web_js.dart`; loaded from Apple's CDN only once iCloud is chosen):
the same `Library` zone, record types and fields CKSyncEngine writes (the
codec's doubles sent as `DOUBLE`, the body as the `body` asset), the change
tag as the version (`CONFLICT`/`EXISTS` looked up for the conflict), the
zone's change feed with its sync token (a refused token lists the zone
again), the zone made on the first save if no iPhone made it, the user
record name as the account (kept while the session runs out, so nothing is
resent). Its session token is kept in local storage. Settings stay in the
browser (the iOS app keeps them in the key-value store, which CloudKit JS
cannot reach). A sign-in also trades the cloud's token for Plus
(`WebCloudPlus`), swapping in the CloudKit token the relay hands back.

**Plus in the browser.** Beside the library, each app writes one record of
its own into the cloud it syncs with, `plus_<device id>` (`PlusDevice`:
its RevenueCat app user id, platform, `lastSeen`, rewritten at most every
six hours; `PlusIdSync`). It goes only into the account sync first ran
with, or one the rider picks in Settings → Sync with: an account change, a
sign-out or sync off forgets locally where it went and stops writing, and
deletes nothing. The browser signs into iCloud or Google and trades that
token at the relay (`POST /plus/web`), which reads the records itself,
ignores those older than 30 days, asks RevenueCat and answers an hour-long
signed Plus token; the browser holds it in memory (`WebPlus`) and sends it
as its bearer. The browser never makes a RevenueCat id.

**Smart loops.** `velorki_loops` is a pure algorithm, no model involved. From a
`LoopRequest` three strategies generate candidates: `RoundtripStrategy` (BRouter
`engineMode=4`, an explicit `direction`) in 8 directions, `ViaOutAndBackStrategy`
(start → via → start, `allowSamewayback=false`) and `PerimeterStrategy` as a
fallback. `RouteScorer` weighs length error, ascent per km against the preferred
band, unpaved share, cycleway and bike-network share, repeated segments and
primary/trunk share; `LoopPlanner.plan()` runs at most 12 with a 25 s timeout.
Every query carries `profile:allow_ferries=0`, and `LoopFilter` drops what is
not a loop before it is scored: a candidate with more than 100 m off the road
network (a ferry, a beeline), more than a tenth of its length ridden twice, or
an invented waypoint that ended up over 500 m from the route it produced. Any of
those is retried with the bearing rotated 18° and the round-trip radius
corrected by how far the answer missed the target; a strategy that has produced
nothing keeps rotating up to three times.

**Assistant.** A card in the Plan tab's sheet slot in place of the planner's
card (no modal: the map beside it stays the map), reading `PlannerState`. A
loop it hands to the loop search brings the card back, on that loop, once the
search is done. On first
open a consent dialog stores `aiConsent: denied | textOnly | withLocation`. The
relay returns a structured `RouteIntent` (loop, point-to-point, or a
modification of the current plan); the pure-Dart `IntentResolver` geocodes its
place names through Photon. The model never returns coordinates and never routes.

## On-device routing

`app/packages/brouter_dart` is a Dart port of BRouter's routing runtime (`core`,
`mapaccess`, `expressions`, `codec`, `util`) — not the map creator, not the HTTP
server. It has no Flutter dependency, runs in an isolate (`lib/isolate.dart`),
and reads the same rd5 tiles and `.brf` profiles as the server. One Dart file
per Java class with the same names, so the port stays diffable against upstream;
`brouter/UPSTREAM_VERSION` (`v1.7.10`) is the pinned tag. `jvm.dart`,
`jfloat.dart` and `jmath.dart` emulate Java `int` overflow, `>>>` and 32-bit
float semantics — that arithmetic is the main determinism risk.

The upstream server is the test oracle: the algorithm is deterministic, so
identical inputs must produce identical output. `tools/brouter-oracle/` records
a 224-case corpus and dumps micro-caches and profile evaluations as JSON from
the pinned server, against two committed rd5 fixtures in
`tools/brouter-oracle/tiles/` (Madeira and SW Iceland, 4.2 MB, pinned by
sha256). Parity has three levels: **L1** byte-identical `util`/`codec` round
trips and rd5 decoding, **L2** bit-identical profile evaluation, **L3**
identical coordinates, length, ascent and messages over the corpus. All three
run on every push as golden tests against the recorded corpus (`app.yml`);
`brouter-oracle.yml` replays the corpus against the real server weekly.

Tiles are 5°×5°, named `E10_N45` / `W5_S10` from `floor(lon/5)*5,
floor(lat/5)*5`, 125–250 MB each in Central Europe, downloaded from
`VELORKI_SEGMENTS_URL` with resumable range requests. That URL is the mirror's
`latest.json` pointer, so a monthly snapshot reaches riders without an app
release; a snapshot is sharded into releases of at most 480 tiles, since each
tile is two assets, the rd5 and its gazetteer, under GitHub's 1000-asset cap,
and `SegmentsManifestService` fetches every shard's `manifest.json` from the
`shards` array and merges them into one manifest whose entries each remember
the release they are served from (one unreadable shard fails the fetch rather
than hiding a region). The app marks tiles the mirror has rebuilt as stale
(checked weekly) and refuses tiles in a newer rd5 format than its bundled
`lookups.dat`, asking for an app update instead. The pointer may also carry
`weatherLayers`, which overrides or switches off the weather map's built-in
sources by `id` (field list on `SegmentsManifestService`); the last one read
is kept for offline use, and anything unreadable means the built-in sources. The map's download button opens `features/offline`,
one screen that fetches the map area and the routing tiles together; the two
kinds keep their own screens behind it. `CompositeRoutingBackend`
takes the bounding box of the waypoints, expands it by max(10 km, 20 %), and
uses `LocalRoutingBackend` when every intersecting tile is present with a
matching `formatVersion`; otherwise the server, if one is configured; otherwise
it offers the download. It never routes locally on partial coverage: BRouter
treats a missing tile as empty land and would silently return a wrong route.

**Place search.** A downloaded region also brings its gazetteer: one small
SQLite file per tile (`<TILE>.gaz`, places, streets and named POIs in one FTS5
index), fetched from the mirror next to the `.rd5` and stored under
`<appSupport>/brouter/gazetteer/`. `GazetteerStore`
(`app/lib/features/search/data/gazetteer_store.dart`) opens every file
read-only and answers the search field first — instant and without a signal.
Every matching row is scored in Dart (`domain/search_text.dart`): how well
each typed word stands for a word of the name (equal, prefix, abbreviation,
typo, compound), how much of the name was asked for, the way to the map
centre, the size of a place and how widely known a row is (`importance`, the
languages its name is given in); Cyrillic and Greek are read in Latin on both
sides, so "aleksandar nevski" finds "Александър Невски"; a town typed after the street ("hauptstrasse
berlin") is matched against each row's place. A query that answers nothing
well gets a second look with the index's own words as alternatives and words
left out; `tools/gazetteer/README.md` has the contract. The app's store
searches on a worker isolate with its own read-only connections, skipping a
lookup that newer typing has already replaced, so a slow one never costs the
UI a frame. A street
whose house numbers the file anchors answers a typed number at the number's
own position, interpolated between the two nearest anchors when it is not one
of them and marked "≈" then; alternative names (`name:en`, `alt_name`, …) are
indexed too and answer under the object's primary name. Typing the name of a
kind instead of a name ("drinking water", "bakery", the localised label) opens
the list with the five nearest rows of that kind, found on the position index
in a box grown from 5 to 50 km around the map centre and shown with their
distance; those rows may be unnamed, and are then titled by their kind.
Settings → Search orders and switches off eight groups (places, streets,
landmarks, cycling stops, overnight, nature, transport, services), which
filters the local results and, once reordered, lifts one group above another.
When the best row only matched through a guessed word, the list says what it
searched for instead. What answers depends on the area, not
on the device: only a map centre inside a tile whose gazetteer is open
(`GazetteerStore.covers`, BRouter's 5° × 5° tile naming) is searched locally,
with Photon the last row of the list ("Search online for …") and "Show offline
results" the way back from an online list; anywhere else — no gazetteer, none
for this area, or no map centre at all — the search goes straight to Photon and
the pinned last row offers "Download this area to search offline", which opens
the offline data screen for the visible area, error state included. A failed
gazetteer download never fails its tile: the region stays routable and its search stays
online. A file whose `meta.schema_version` is not the one this build reads, or
that will not open at all, is skipped with a log line: the other tiles keep
answering and that area searches online. The files are built by
`tools/gazetteer`.

## Configuration

Everything environment-specific comes from `String.fromEnvironment`, collected
in `AppConfig`. Builds pass `--dart-define-from-file=env/<name>.json`; `dev`,
`ci` and `example` are committed, `local.json` and `phone.json` are git-ignored.

| Variable | Meaning |
|---|---|
| `VELORKI_BROUTER_URL` | a BRouter routing server. Empty: on-device routing only |
| `VELORKI_API_URL` | the relay. Empty: no assistant, no integrations, no sharing |
| `VELORKI_SEGMENTS_URL` | the rd5 segment mirror for on-device routing |
| `VELORKI_PHOTON_URL` | the Photon geocoder |
| `VELORKI_MAP_STYLE_URL` / `_DARK` | the MapLibre style, light and dark |
| `VELORKI_CYCLOSM_TILE_URL` | CyclOSM raster tiles for the optional overlay |
| `VELORKI_REVENUECAT_KEY_ANDROID` / `_IOS` | RevenueCat public SDK keys |
| `VELORKI_STRAVA_CLIENT_ID`, `VELORKI_RWGPS_CLIENT_ID` | public OAuth client ids; the secrets stay in the relay |
| `VELORKI_OAUTH_SCHEME` | the custom scheme for OAuth redirects and share links |
| `VELORKI_STORE_URL_ANDROID` / `_IOS` | the store page, opened when a tile needs a newer app. Empty: the rider is only told |

Settings → Advanced overrides the server URLs at runtime.

## Free vs Plus

Free is everything that runs on the phone, plus the Strava and Ride with GPS
connections (Strava's API Policy forbids charging for its functionality; Ride
with GPS follows for consistency). Plus is what needs our servers: the
assistant, link sharing, and the weather through the relay (the route
forecast from NWS, DWD MOSMIX and MET Norway, and the OPERA and DPC radars). The weather
map and the route weather from the DWD's open ICON forecast (wind, rain and 2 m
temperature: the route's weather section, its best time and its colours) stay
free: the phone fetches them itself. `app/lib/core/plus/plus_gate.dart` is the switch.

## Licences

AGPL-3.0-only for the whole repository — app, packages, site, relay, profiles,
deploy files, tools and docs — so that a fork publishes its changes whether it
ships a modified app or runs a modified relay. `LICENSE` at the root is the only
licence file. Distribution through the App Store and Google Play works because
Orkitec holds the copyright on the code and can license it under other terms as
well; outside contributions therefore need the Contributor Licence Agreement in
`CLA.md`, checked by `.github/workflows/cla.yml`. Versions released before the
relicensing commit stay available under Apache-2.0 from the git history.
`TRADEMARK.md` reserves the name, logo and icon: forks must rebrand before
publishing to a store and may not point at the official servers.
