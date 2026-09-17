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
are built from), OpenFreeMap and CyclOSM (map tiles), Photon (online search).

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
 CyclOSM        online search,    (optional):       Plus only: OAuth
 map tiles      no tiles needed   areas with no     exchange, LLM,
                                  tiles             share links
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
them, and the store for share links. No accounts, no cloud database, no sync.

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
                              │  RideWithGPS; the phone then talks to them direct
                              ├─ AI: prompt → an OpenAI-compatible LLM provider
                              └─ share links
```

## App architecture decisions

| Topic | Choice | Why |
|---|---|---|
| State and DI | Riverpod 3 with `riverpod_annotation` codegen, no `get_it` | doubles as dependency injection; testable through `ProviderContainer(overrides:)` |
| Persistence | Drift 2 (SQLite) for routes, rides, offline regions and tiles; `shared_preferences` for settings; `flutter_secure_storage` for OAuth tokens | typed SQL, migrations, streams |
| Geometry storage | one packed `BLOB` per route or ride (`velorki_geo/PackedTrack`: lat f64, lon f64, ele f32, timeMs i64, speed f32, acc f32 = 36 bytes per point, with a version byte) | 10k points are one row of 360 KB instead of 10k rows; the same format is the recording journal |
| Navigation | go_router with `StatefulShellRoute` and four tabs (Plan, Record, Library, Settings); deep links through `app_links` | few routes, so no `go_router_builder` |
| Codegen | freezed, json_serializable, drift_dev, riverpod_generator, gen-l10n; generated files are not committed, `app/tool/gen.sh` runs them | |
| HTTP | dio | interceptors for token refresh, the rate-limit bucket, multipart, cancellation |
| Map | maplibre_gl behind a `MapController` interface so widget tests can fake it; style URL from config | BSD-licensed, vector tiles, offline regions. Mapbox is proprietary and metered per monthly active user |
| Map tiles | OpenFreeMap vector tiles by default, CyclOSM raster as an optional overlay | no key, no limits; swappable to self-hosted PMTiles |

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

`buildLightTheme(preset)` / `buildDarkTheme(preset)` with four accent presets
(`AccentPreset`: volt, ember, glacier, berry), chosen under Settings →
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
| `velorki_api` | the client for the relay |
| `brouter_dart` | the Dart port of the BRouter routing runtime |

`RoutingBackend` is the seam that keeps the planner free of where a route comes
from: it only ever calls `route()`.

## Data model

Drift owns four tables, schema version 3. Connected accounts live in secure
storage, not in the database.

- **`routes`** — id (uuid), name, description, `source`
  (`planned|loop|imported_gpx|imported_fit|strava|rwgps`), profile, timestamps,
  distance, ascent, descent, bbox, the geometry blob, and waypoints, routing
  options, surface stats, external ids and `external_fetched_at` as JSON.
- **`rides`** — id, name, start and end, distance, moving and elapsed time,
  ascent, descent, average and maximum speed, an optional `route_id`, the
  geometry blob including time, pauses, uploads, notes.
- **`offline_regions`** — the downloaded MapLibre offline map regions.
- **`routing_tiles`** — the rd5 segment tiles downloaded for on-device routing:
  name, bytes, `updated_at`, `format_version`, state.

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

**Recording that survives an app kill.** The recorder appends 36-byte
`PackedTrack` records to `<appSupport>/recording/<rideId>.vtj`, flushing every
5 points or 10 seconds, next to a `recording_state.json`. On launch
`RecoveryService` reattaches to a running recording or offers Resume/Finish for
an orphaned one; finalising computes the statistics (moving time at 1 km/h,
ascent with 3 m hysteresis) and writes the `rides` row. On Android
the `flutter_foreground_task` isolate owns the geolocator stream, the journal
and the live statistics; the manifest deliberately does **not** request
`ACCESS_BACKGROUND_LOCATION`, because the service always starts in the
foreground, which avoids the stricter Play review. On iOS "When In Use" plus
`UIBackgroundModes location` suffices. While a ride runs the camera follows
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
kilometre or mile splits, at most 400 smoothed chart samples for the elevation
and speed charts, and the track cut into five speed classes by its own
quantiles, which the ride page draws through `MapController.setTrackSegments`.


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
(`flutter_tts`) says it. Three switches in Settings: `navigation.turns` shows
the banner, `navigation.voice` speaks it, `navigation.reroute` repairs a ride
that has gone astray. The same three are chips on the record sheet, and the
banner carries a mute button that silences the voice for the rest of the ride
only (`voiceMutedForRideProvider`, cleared whenever a ride starts or ends).
On iOS the speaker holds one audio session for the whole spoken stretch rather
than the one per cue `flutter_tts` would otherwise take and give back, and each
cue is preceded by 1.5 s of silence (`assets/audio/silence.wav`, played by
`AppDelegate` over `app.velorki/audio`). Both are for Bluetooth headsets, whose
A2DP link goes idle between cues and takes about a second to come back — long
enough to swallow the first syllables of a turn.
A rider who leaves the route is repaired in three steps, and `OffRouteMachine`
decides which: more than `max(75 m, 2 × accuracy)` out for two fixes (or 8 s) is
`guiding`, where the
plan stays the active route and the banner and the voice point at the nearest
route point still ahead, with a distance and a left/right/ahead/behind taken
from the bearing minus the rider's heading — no routing at all, because most
strays are a wrong turn undone within a block. Still off 30 s or 150 m later, or
on a tap, it is `detour`: candidates 300 m, 800 m and 2 km further along the plan
are routed from the rider in that order (through a via point 40 m along their
heading above 1.5 m/s, BRouter having no heading parameter) and the first whose
length is at most 3× the beeline to it wins — a bigger multiple is a river or a
one-way, so the next candidate is tried, and if all three loop the shortest of
them is taken. The goal is the nearest way back onto the plan, not the shortest
way to the finish, which is only ever a candidate when it falls inside the 2 km
window. The answer is stitched to the rest of the plan as one
route in `detourRouteProvider` — drawn as a branch beside the plan, recomputed
only on a `max(50 m, 2 × accuracy)` drift and at most every 20 s. Within
`max(30 m, accuracy)` of the plan again the branch is dropped silently and its
hints carry on. Every one of those distances scales with the fix's reported
horizontal accuracy the way OsmAnd and Organic Maps do, capped at 100 m of
accuracy so a phone that has lost the sky cannot switch off-route detection off
(`off_route_thresholds.dart` holds the two formulas and the constants). Only an explicit
"New route from here", or 3 km out for over 5 minutes, re-plans the whole ride to
its destination; `navigation.reroute` off leaves the rider with the guidance and
nothing more.

**Integrations and OAuth.** One `OAuthFlow`: build the authorise URL, open it
with `flutter_web_auth_2`, receive the redirect on `velorki://oauth/<service>`,
exchange the code **through the relay**, store the tokens in secure storage; a
dio interceptor refreshes 60 s before expiry. Strava rides go up as multipart
uploads, polled with backoff and then linked to; the imported route list is
cached for 7 days, a client-side bucket keeps reads under 90 per 15 minutes, and
AI descriptions are refused for `source == strava`. Strava's API cannot create
routes, so sending one *to* Strava is "export GPX, then share"; Komoot and
Garmin are file-based only.

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

**Assistant.** A bottom sheet over the planner, reading `PlannerState`. On first
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
`lookups.dat`, asking for an app update instead. The map's download button opens `features/offline`,
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
read-only and answers the search field first — instant and without a signal —
ranked by bm25, then population, then distance to the map centre. A street
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
filters the local results and breaks bm25 ties before name length does. A query
that matches nothing is run once more against the index vocabulary
(`fts5vocab` in the connection's `temp` schema, Damerau-Levenshtein), and the
list says what it searched for instead. What answers depends on the area, not
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

Free is everything that runs on the phone. Plus is everything that needs our
servers or a partner account: the assistant, the Strava and RideWithGPS
connections, link sharing. `app/lib/core/plus/plus_gate.dart` is the switch.

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
