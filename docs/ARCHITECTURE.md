# Architecture

This is the design document for contributors. It explains what Velorki is made
of, which decisions were taken and why, and in what order the work happens.
Reading it end to end takes about twenty minutes.

## The guiding rule

**As much as possible runs on the device.**

The phone holds the routes, the rides, the loop generator, the file import and
export, and — once the Dart port of BRouter lands — the routing itself. The
server side exists only for the things an open-source app cannot do on its own:

- the routing graph, which is too large to ship in an app bundle (BRouter);
- the secrets: the Strava and RideWithGPS OAuth client secrets and the API key
  of the language model;
- the hosted language model behind those secrets;
- the store for share links.

That is the whole list. There are no accounts, no cloud database and no sync in
v1. Every later feature is measured against the same rule: if it can run on the
phone, it runs on the phone.

## Components

```
                         ┌──────────────────────────┐
                         │  Phone (Flutter app)     │
                         │  routes, rides, loops,   │
                         │  GPX/FIT, recording,     │
                         │  brouter_dart (track R)  │
                         └───┬───────┬──────┬───────┘
                             │       │      │
   route requests (waypoints)│       │      │ map tiles / search
                             │       │      └──────────────► OpenFreeMap
                             │       │                       CyclOSM
                             │       │                       Photon
                             ▼       │
              ┌────────────────────┐ │
              │ BRouter server     │ │
              │ (self-hosted, JVM) │ │
              │ rd5 segment tiles  │ │
              └────────────────────┘ │
                                     │  OAuth code exchange, AI, share links
                                     ▼
                        ┌────────────────────────┐
                        │ Relay (api/, Node 22)  │
                        │ no accounts, no user DB│
                        └───┬───────────┬────────┘
                            │           │
          token exchange    │           │  prompts
          (secrets added)   │           │
                            ▼           ▼
                    Strava / RideWithGPS      LLM provider
                            ▲                 (OpenAI-compatible)
                            │
              uploads and downloads go
              phone → service directly,
              with the phone's own tokens
```

Two things are worth noting in that picture:

- The relay never proxies ride data. It exchanges an OAuth code for a token and
  hands the token back; from then on the app talks to Strava and RideWithGPS
  directly with tokens kept in `flutter_secure_storage` on the phone.
- Map tiles and search do not pass through our servers either. The app talks to
  OpenFreeMap, CyclOSM and Photon directly.

## App architecture decisions

| Topic | Choice | Why |
|---|---|---|
| State and DI | Riverpod 3 with `riverpod_annotation` codegen, no `get_it` | doubles as dependency injection; `AsyncNotifier` fits the HTTP-heavy features; testable through `ProviderContainer(overrides:)` |
| Persistence | Drift 2 (SQLite) for routes, rides and tiles; `shared_preferences` for settings; `flutter_secure_storage` for OAuth tokens | typed SQL, migrations, streams. Isar is unmaintained, Hive has no queries |
| Geometry storage | one packed `BLOB` per route or ride (`velorki_geo/PackedTrack`: lat f64, lon f64, ele f32, timeMs i64, speed f32, acc f32 = 36 bytes per point, with a version byte) | 10k points are 360 KB in one row instead of 10k rows; the same format is the recording journal |
| Navigation | go_router 16 with `StatefulShellRoute` and four tabs (Plan, Record, Library, Settings); deep links through `app_links` | few routes, so no `go_router_builder` |
| Codegen | freezed 3, json_serializable, drift_dev, riverpod_generator, gen-l10n; generated files are not committed; `tool/gen.sh` runs them | |
| HTTP | dio 5 | interceptors for token refresh, the rate-limit bucket, multipart and cancellation |
| Map | maplibre_gl 0.27 behind a `MapController` interface so widget tests can fake it; style URL comes from config | BSD-licensed, vector tiles, offline regions. `flutter_map` was rejected (vector plugin pinned to an old version, bulk-cache plugin is GPL); Mapbox was rejected (proprietary, metered per monthly active user) |
| Map tiles | OpenFreeMap vector tiles by default (no key, no limits, commercial use allowed), CyclOSM raster as an optional overlay | the tile source stays swappable to self-hosted PMTiles |
| Monorepo | Dart pub workspace declared in the root `pubspec.yaml`, no melos | |

Key packages are pinned to exact versions at M0: flutter_riverpod 3, go_router
16, freezed 3, drift 2, sqlite3_flutter_libs, flutter_secure_storage 9,
maplibre_gl 0.27, geolocator 14, flutter_foreground_task 9, permission_handler
12, wakelock_plus, gpx 2.5.0, fit_sdk 0.3.0, xml 6, file_picker 10, share_plus
11, receive_sharing_intent 1.9.0, app_links 7, flutter_web_auth_2 5,
url_launcher, dio 5, purchases_flutter 9, fl_chart 1, uuid 4, mocktail 1.

Deliberately not used: `strava_client` (it expects the client secret inside the
app; we write a six-endpoint client instead) and `latlong2` (we have our own
geometry package).

## Layout

The repository is one monorepo so that app and relay change in the same commit
and a fork can self-host from a single clone.

```
velorki/
├── app/            Flutter app (Apache-2.0)
│   └── packages/   the pure-Dart packages, including brouter_dart
├── api/            the relay, Node 22 + TypeScript (AGPL-3.0-only)
├── brouter/        custom .brf profiles, the rd5 updater image
├── deploy/         compose file, Caddy, systemd units, README for forks
└── docs/           this document, ADRs, privacy, store checklist
```

Inside `app/lib` the layout is feature-first, and every feature has
`data/`, `domain/` and `presentation/`:

```
features/{map, planner, library, recording, import_export,
          integrations/strava, integrations/rwgps,
          smart_loop, assistant, subscription, settings}
core/{db, http, geo, files, permissions}
app/{router, theme, app_config, bootstrap}
l10n/app_en.arb  + the translated locales
```

Only `app_en.arb` is edited by hand; the other ARB files come from the GL
Strings integration.

### Pure-Dart packages (`app/packages/`)

None of these depend on Flutter, so they run and are unit-tested on the desktop
Dart VM.

| Package | Owns |
|---|---|
| `velorki_geo` | `LatLng`, distance, bearing, bounding boxes, and the packed geometry codec |
| `velorki_gpx` | GPX reading and writing, wrapping `gpx` 2.5 |
| `velorki_fit` | FIT activities and courses, wrapping `fit_sdk` 0.3 |
| `velorki_brouter` | HTTP client for the BRouter server, the GeoJSON and `messages` parser producing `RouteResult`, and the `RoutingBackend` interface |
| `velorki_loops` | the loop candidate strategies and the scorer |
| `velorki_api` | the client for the relay |
| `brouter_dart` | the Dart port of the BRouter routing runtime (see "On-device routing" below) |

`RoutingBackend` is the seam that makes on-device routing possible later
without touching the planner: the planner only ever calls `route()`.

## Data model

Drift owns four tables. Connected accounts are not in the database; they live
in secure storage.

**`routes`** — id (uuid), name, description, `source`
(`planned|loop|imported_gpx|imported_fit|strava|rwgps`), profile, created and
updated timestamps, distance, ascent, descent, bbox, the geometry blob,
waypoints JSON, routing options JSON, surface stats JSON, external ids JSON,
`external_fetched_at` (Strava's cache must be dropped after 7 days), and
`ai_description_generated`.

**`rides`** — id, name, started and ended timestamps, distance, moving and
elapsed time, ascent, descent, average and maximum speed, an optional
`route_id`, the geometry blob including time, pauses JSON, uploads JSON, notes.

**`offline_regions`** — the downloaded MapLibre offline map regions.

**`routing_tiles`** — name, bytes, `updated_at`, `format_version`, state: the
rd5 segment tiles downloaded for on-device routing.

## Key flows

### Planner

Ordered waypoints plus `RoutingOptions{profile, alternativeIdx}`. Edits are
debounced 300 ms and then call `RoutingBackend.route()`. The `RouteResult`
carries the geometry, the ascent and BRouter's `messages` (way tags per
segment), from which the surface statistics are derived. The user can drag the
line to insert a via point, sees an elevation profile (fl_chart), can switch
between alternatives 0–3 and has an undo stack. Search is Photon, debounced
250 ms, from three characters. Saving writes one `routes` row.

### Import and export

`IncomingFileService` unifies the two ways a file arrives: open-with (via
`app_links` and `content://` URIs) and the share sheet (via
`receive_sharing_intent`). The file type is decided by sniffing the bytes —
`<gpx` or `<?xml` versus the FIT header at offset 8 — not by trusting the MIME
type. A preview screen shows what was found; the presence of timestamps decides
whether it becomes a route or a ride.

Export writes GPX (route or track) and FIT (course or activity) and hands the
file to `share_plus`, which covers "open in Komoot" and "open in Garmin
Connect", or saves it to Files.

Platform registration matters here and is easy to forget:

- iOS: `UTImportedTypeDeclarations` for `com.topografix.gpx` and our own FIT
  type, plus `CFBundleDocumentTypes`.
- Android: intent filters for `application/gpx+xml`, `application/gpx`,
  `application/vnd.ant.fit`, and `application/octet-stream` with
  `pathPattern .*\.gpx`.

### Recording that survives an app kill

The recorder appends 32-byte records to `<appSupport>/recording/<rideId>.vtj`
and flushes every 5 points or 10 seconds, next to a
`recording_state.json {rideId, startedAt, status, routeId?}`. On launch,
`RecoveryService` either reattaches to a running recording or offers
Resume/Finish for an orphaned one. Finalising computes the statistics (moving
time with a 1 km/h threshold, ascent with 3 m hysteresis) and writes the
`rides` row.

On Android the `flutter_foreground_task` isolate owns the geolocator stream
(`distanceFilter` 5, best accuracy), the journal and the live statistics; the
service is `START_STICKY` and its notification shows distance and time.
Permissions are fine location, foreground service location and notifications —
deliberately **not** `ACCESS_BACKGROUND_LOCATION`, because the service always
starts in the foreground, which avoids the stricter Play review. The
battery-optimisation exemption is offered once.

On iOS it is `UIBackgroundModes location` with
`pausesLocationUpdatesAutomatically = false` and the background indicator on;
"When In Use" authorisation is sufficient. Relaunch after termination through
significant-location-change (a small Swift channel) is a stretch goal. The app
ships a `PrivacyInfo.xcprivacy`.

### Integrations and OAuth

One `OAuthFlow` abstraction: build the authorise URL, open it with
`flutter_web_auth_2` (for Strava, try the app-to-app URL
`strava://oauth/mobile/authorize` first and fall back to the web), receive the
redirect on `velorki://oauth/<service>`, exchange the code **through the
relay** (which adds the client id and secret), store the tokens in secure
storage. A dio interceptor refreshes 60 seconds before expiry.

Strava: rides are uploaded as multipart `POST /uploads` (GPX or FIT), the
upload is polled with 2/4/8 s backoff, and the app then links to the activity.
Routes are imported through `/athletes/{id}/routes` and
`/routes/{id}/export_gpx`. A client-side bucket keeps reads under 90 per 15
minutes, the imported list is purged after 7 days, and AI descriptions are
disabled for `source == strava`. Strava's API does not allow creating routes,
so sending a route *to* Strava is "export GPX, then share", and the UI says so.

RideWithGPS: `POST /routes.json` and `POST /trips.json` as multipart plus task
polling, `GET /routes/{id}.gpx`, `GET /trips`. Komoot and Garmin are
file-based only; Garmin developer access has been paused since 2026.

### Smart loops

`velorki_loops` is a pure algorithm with no model involved. From
`LoopRequest{start, via[], targetM, profile, prefs{hills, surface,
avoidTraffic}}` three strategies generate candidates:

- `RoundtripStrategy` — BRouter's round-trip mode (`engineMode=4`, `roundTripDistance` is a radius in metres, route ≈ (π+2)·radius, `roundTripStartDirection`) in 8 directions, then
  the best two re-issued with the distance scaled by target/actual.
- `ViaOutAndBackStrategy` — start → via → start with `allowSamewayback=false`.
  If the result is too short, a synthetic bearing point perpendicular to the
  chord is added and a secant search on distance converges; if it is too long,
  the app reports "via too far".
- `PerimeterStrategy` — three or four points on a circle of radius target/2π,
  as a fallback.

`RouteScorer` is a weighted sum of normalised length error, ascent per km
against the preferred band, unpaved share, cycleway and bike-network share,
repeated-segment ratio (hashes of rounded coordinate pairs) and
primary/trunk share. `LoopPlanner.plan()` runs at most 12 candidates,
concurrency 3 against the server and sequentially on device, with a 25 s
timeout, and shows the top three as alternatives.

Fixtures of recorded BRouter GeoJSON make the whole pipeline testable offline.

### Assistant

A bottom sheet over the planner with read access to `PlannerState`. On first
open a consent dialog stores `aiConsent: denied | textOnly | withLocation`. The
sheet sends the text to the relay, which returns a structured `RouteIntent
{kind loop|pointToPoint|modify, start, via[], end?, targetDistanceKm?,
profile?, hills, surface, avoidTraffic, notes}`. The pure-Dart `IntentResolver`
geocodes the place names through Photon, biased to the current position, and
builds waypoints or a `LoopRequest`. Ambiguous names become chooser chips;
`kind == modify` applies a diff to the current plan. "Describe this route" is
optional and can be turned off.

The model never returns coordinates and never does the routing — routing stays
in the app. Low confidence makes the app ask a follow-up question locally.

### Subscription

`SubscriptionService` wraps `purchases_flutter` with an anonymous app user id,
exposes a `hasPlus` stream from `CustomerInfo.entitlements.active`, and the
paywall has a restore button that works without any login. A 7-day free trial
runs through the store subscription so the integrations can be tried.

## Configuration

Everything environment-specific comes from `String.fromEnvironment` and is
collected in `AppConfig`. Builds pass `--dart-define-from-file=env/<name>.json`;
the official defaults are committed, `env/local.json` is git-ignored.

| Variable | Meaning |
|---|---|
| `VELORKI_BROUTER_URL` | the BRouter routing server |
| `VELORKI_API_URL` | the relay |
| `VELORKI_PHOTON_URL` | the Photon geocoder |
| `VELORKI_MAP_STYLE_URL` | the MapLibre style |
| `VELORKI_SEGMENTS_URL` | the rd5 segment mirror used for on-device routing |
| `VELORKI_REVENUECAT_KEY_ANDROID` | RevenueCat public SDK key, Android |
| `VELORKI_REVENUECAT_KEY_IOS` | RevenueCat public SDK key, iOS |
| `VELORKI_STRAVA_CLIENT_ID` | Strava OAuth client id (the secret stays in the relay) |
| `VELORKI_RWGPS_CLIENT_ID` | RideWithGPS OAuth client id |
| `VELORKI_OAUTH_SCHEME` | the custom scheme used for OAuth redirects |

**An empty `VELORKI_API_URL` hides the AI assistant, Strava, RideWithGPS and
link sharing entirely.** That is the pure-local fork build: planning,
recording, files and loops, with nothing of ours involved.

Settings → Advanced lets users override the server URLs at runtime.

## On-device routing (track R)

The goal is that the routing server becomes optional. `app/packages/brouter_dart`
is a Dart port of BRouter's routing runtime.

**Scope.** Only the runtime: `brouter-core` (33 files), `brouter-mapaccess`
(20), `brouter-expressions` (10, the `.brf` profile interpreter),
`brouter-codec` (11), `brouter-util` (27). Not the map creator, not the HTTP
server, not the Android app. The port is a pure-Dart package with no Flutter
dependency, run in an isolate, so there is one codebase for both platforms, no
FFI toolchain, and desktop-VM unit tests. Kotlin Multiplatform and Rust were
considered and rejected: a second toolchain plus a native bridge for no benefit
at bike-route scale.

**Fidelity discipline.** One Dart file per Java class with the same names, so
the port stays diffable against upstream; `UPSTREAM_VERSION` is pinned to the
same tag as the Docker image. A `jvm.dart` helper emulates Java `int` overflow
(`toSigned(32)`), the difference between `>>>` and `>>`, and `float` fields via
`Float32List` round-trips — that arithmetic is the main determinism risk. No
behavioural "improvements" until parity is green.

**The oracle.** The self-hosted BRouter is the test oracle: the algorithm is
deterministic, so identical inputs must produce identical geometry and cost.
`tools/brouter-oracle/` (Java, upstream jars, runs in Docker in CI) dumps rd5
micro-caches as JSON, dumps profile evaluations, and generates a corpus of
request plus full GeoJSON (geometry, length, filtered and plain ascent,
messages) from the pinned server. Fixtures are a mini rd5 built from a small
Geofabrik extract (Liechtenstein or Malta, under 10 MB) in Git LFS; a nightly
job runs against two real tiles. Parity is checked at three levels:

- **L1** — byte-identical `util` and `codec` round trips and dumps.
- **L2** — profile evaluation equal to within 1e-6.
- **L3** — identical coordinates, length, ascent and messages for 200+ cases
  across the trekking, fastbike, mtb and gravel profiles, alternatives 0–3,
  nogos and roundtrip, with timeouts disabled on both sides.

**Memory strategy.** BRouter runs in a 128 MB JVM using random-access reads, so
the port does the same: a `RoutingWorker` isolate with synchronous
`RandomAccessFile` reads (upstream does not mmap), one handle per rd5 file, and
a two-level cache — raw micro-cache bytes in an LRU of about 16 MB, decoded
`MicroCache` objects under upstream's own `maxmem` accounting (64 MB default,
128 MB on devices with 6 GB or more) with the same "collect unreferenced" pass.
A whole rd5 file is never loaded into memory. Cancellation is cooperative,
checked every ~2000 expansions. The target after R5 is a 60 km trekking route
in under 3 s on a mid-range 2023 Android with an isolate heap below 150 MB.

**Composite backend rule.** `CompositeRoutingBackend` takes the bounding box of
the waypoints, expands it by max(10 km, 20 %), and determines the intersecting
5° tiles. If all of them are present locally with a matching `formatVersion`,
it uses `LocalRoutingBackend`; otherwise the server, if one is configured;
otherwise it offers "download N tiles (X MB)". It never routes locally on
partial coverage, because BRouter treats a missing tile as empty land and would
silently return a wrong route.

**Region download.** Tiles are named `E10_N45` / `W5_S10` from
`floor(lon/5)*5, floor(lat/5)*5`. Entry points are the current viewport, the
route detail screen ("needed for offline routing: 2 tiles, 640 MB") and the
fallback error, with a grid overlay on the map. Sizes come from
`${VELORKI_SEGMENTS_URL}/manifest.json` on our own mirror, with the brouter.de
directory listing as a fallback. Downloads are resumable range requests through
dio, written to `.part` and atomically renamed, size- and hash-checked, Wi-Fi
only by default, with an Android `dataSync` foreground notification. Tiles live
in `<appSupport>/brouter/segments/` and are excluded from iOS backup. Profiles
and `lookups.dat` ship as app assets from the pinned release. Tiles whose
format version does not match are refused. rd5 delta updates are deferred.

For scale: the planet is 1142 tiles and 10.0 GB (measured 2026-09-12); a
Central-European tile is 125–250 MB, Germany is about 760 MB. That is the same
order as OsmAnd or Komoot offline regions. The VPS mirrors the full set weekly
so the app never depends on brouter.de.

**Placement.** Track R runs alongside the milestones:

| | Scope | Alongside |
|---|---|---|
| R0 | oracle harness | M1 |
| R1 | `util` + `codec` | M2 |
| R2 | `mapaccess` | M3 |
| R3 | `expressions` | M4 |
| R4 | `core`, the worker isolate, the composite backend, region download, an "On-device routing (beta)" toggle | M5–M6 |
| R5 | performance, delta updates, on-device by default with server fallback, server URL optional | v1.1 |

If R4 lands before M7 the beta toggle is in v1; otherwise it ships in v1.1
without changing the store submission.

## The relay's API contract

The contract is `api/openapi.yaml`. All errors share one shape:

```json
{ "error": { "code": "...", "message": "...", "retry_after_s": 30 } }
```

with codes `invalid_request` (400), `not_entitled` (401), `consent_required`
(403), `rate_limited` (429), `upstream_error` (502) and `unavailable` (503).
Every request carries `X-Velorki-Client: ios/1.2.0+45` for the logs.

| Endpoint | What | Limits |
|---|---|---|
| `GET /health` | status, git sha, BRouter ok/degraded (cached 60 s), whether the LLM is configured. No auth. | — |
| `POST /oauth/strava/token` | `{code, redirect_uri}` → the Strava token response passed through; the relay adds client id and secret and exact-matches `redirect_uri` against an allowlist | 10/min and 60/day per IP |
| `POST /oauth/strava/refresh` | `{refresh_token}` → passthrough | 30/h per IP |
| `POST /oauth/rwgps/token` | `{code, redirect_uri}` → passthrough (RideWithGPS has no PKCE, so the relay holds the secret) | as above |
| `POST /oauth/rwgps/refresh` | stubbed `501` unless RideWithGPS starts issuing refresh tokens | — |
| `POST /ai/plan` | SSE. Headers `Authorization: Bearer <revenuecat_app_user_id>` and `X-AI-Consent: 1` (403 without it). Body `{step: "plan"\|"describe", locale, units, prompt, context{start rounded to 2 decimals, start_label?}, route_summary?}` | 20/h and 100/day per user, 60/h per IP |
| `POST /share` | stores GPX plus metadata and returns `https://velorki.app/s/<id>`; entitled users only | to be decided |
| `GET /s/<id>` | a small static page: map preview, statistics, an "Open in Velorki" deep link, GPX download. Free, no account. | to be decided |

`POST /ai/plan` emits four SSE event types: `route_request` (the structured
result, once), `text` (deltas), `done` (usage and model) and `error`.

**Entitlement.** The relay calls
`GET https://api.revenuecat.com/v1/subscribers/{app_user_id}` with the secret
REST key and checks whether the entitlement is active, with an LRU cache of 10
minutes for positive and 1 minute for negative answers. This check guards both
`/ai/plan` and the OAuth endpoints, where it doubles as their authentication.
`REVENUECAT_MODE=stub` lets forks run the endpoints open. There is no app
attestation in v1 (a hook header is reserved); the OAuth endpoints rely on
single-use codes, the redirect allowlist and per-IP limits. A global
`LLM_DAILY_BUDGET_USD` circuit breaker returns 503 when it trips.

**The model.** The relay uses the Vercel AI SDK with
`@ai-sdk/openai-compatible`, configured by `LLM_BASE_URL`, `LLM_API_KEY` and
`LLM_MODEL`, so OpenAI, a self-hosted vLLM or Ollama, and Anthropic's
compatibility layer are a configuration change; `getModel()` is the single
switch point. `step=plan` is one call with `tool_choice: required` on the tool
`propose_route`, whose zod schema is strict: `distance_km` (5–300), `loop`,
`start {use_current, name?}`, `via[]` (place names, at most 4 — the app
geocodes them), `surface` paved|mixed|gravel, `hills` avoid|neutral|seek,
`traffic_tolerance` low|medium|high, `stops[]`, `profile_hint`
trekking|fastbike|mtb|gravel, `notes` (≤200 chars) and `confidence` (0–1).
`step=describe` streams a 60–90 word description from a compact route summary
and can be disabled by the user. The system prompt is versioned at
`api/src/ai/prompts/plan.v1.md`.

For Apple's 5.1.2(i) the data sent is minimised: the start position is rounded
to about 1 km, there are no identifiers in the prompt, consent is a one-time
screen and it is revocable in settings.

## Monetisation

Free is everything that runs on the phone. **Velorki Plus** is everything that
needs our servers or a partner account.

| Free | Plus |
|---|---|
| map, planning, profiles, alternatives, elevation, search | AI assistant (hosted model via the relay) |
| smart loops (algorithmic, on device or via the routing server) | Strava: ride upload, route import |
| ride recording, library, statistics | RideWithGPS: routes and trips both ways |
| GPX/FIT import and export through files and the share sheet — the free path into Strava, Komoot and Garmin | link sharing of routes and rides (`velorki.app/s/<id>`) |
| offline map regions, on-device routing tiles once track R lands | later: cloud sync across devices |

The entitlement is called `plus`. (The API draft in the plan still writes
`smart`; the exact string configured in RevenueCat is to be decided, but there
is only one entitlement.)

A single `PlusGate` configuration lists which features are gated, so moving one
— making Strava upload free as an acquisition hook, say — is a one-line change.
When a subscription lapses, existing tokens keep working until the end of the
entitlement period; after that the app hides the integrations and keeps all the
data.

Gating integrations behind in-app purchase is permitted as a digital feature
unlock. Forks unlocking everything is expected under Apache-2.0; what the
subscription actually buys is the official Strava and RideWithGPS client ids,
the relay and the trademark.

## Deployment

| Piece | How it runs |
|---|---|
| BRouter | Java, so either a container (pinned upstream release, `-Xmx512M`, segments volume read-only, custom profiles mounted, healthcheck = a tiny route) or a systemd `java -jar` unit with the segment updater as a cron job. `deploy/` documents both; the container is the default. |
| Segment updater | weekly rd5 mirror from brouter.de with an atomic swap and a `SEGMENT_FILTER` glob for regional forks. The first planet sync takes 1–3 h. |
| Relay (`api/`) | **deployed and managed by Orkify as a plain Node process** — zero-downtime deploys, logs, process management — not a hand-rolled Docker/SSH pipeline. The Dockerfile and GHCR image remain an option for forks that prefer containers. |
| TLS | Caddy in front, automatic Let's Encrypt. |

**Dependency rule for `api/`: everything must run on stock Node 22+ with no
native addons and no edge/Bun/Deno-only packages.** Concretely: Fastify, zod
and pino (pure JS), the Vercel AI SDK with `@ai-sdk/openai-compatible` (pure
JS), the built-in `fetch`/`undici`, and `node:sqlite` (built into Node 22.5+)
for the share store instead of `better-sqlite3`. CI runs
`npm ci --omit=optional` and fails if any dependency has a `binding.gyp` or an
install script.

Sizing: the planet rd5 set is 10–14 GB, so provision 40 GB of disk (twice the
set for the atomic refresh, plus growth); 4 GB RAM is comfortable and 2 GB
works for a regional set; 1 vCPU serves several routes per second. The only
things to back up are `deploy/.env` and the share-link SQLite file (plus
Caddy's certificate volume).

## Milestones

| | Scope | Done when |
|---|---|---|
| **M0** Scaffold | toolchain installed; workspace, `app/`, empty packages compile; Riverpod and go_router shell with four tabs; Drift with `routes`/`rides` and a migration test; `AppConfig` and `env/dev.json`; l10n and the GL Strings action; CI analyze/test/debug APK; licences, TRADEMARK, this document; `deploy/` with Caddy and BRouter (Europe tiles first) | `flutter test` green in CI; the debug APK installs; a route request against the VPS BRouter returns GeoJSON |
| **M1** Map and planning | MapLibre with OpenFreeMap, location puck, attribution, CyclOSM toggle, waypoints, BRouter routing with profiles and alternatives, elevation profile, surface stats, Photon search, save and load, offline map regions | a 50 km route with 3 vias in under 2 s on device; it survives a restart; parser unit tests pass |
| **M2** GPX/FIT | `velorki_gpx` and `velorki_fit`, open-with and share intake on both platforms, byte sniffing, preview, export through the share sheet | a Komoot GPX opens into Velorki from Files; an exported FIT course passes FitCSVTool; round-trip tests pass |
| **M3** Recording | foreground service and background location, journal and recovery, live stats, auto-pause, follow-route overlay, ride finalise/detail/export | a 2 h screen-off ride on both platforms with no gaps; killing the app mid-ride keeps recording on Android; force-quit then resume restores all points |
| **M4** Strava and RideWithGPS | relay deployed, connect and disconnect, Strava upload with polling and a link, Strava route import, RideWithGPS route and trip upload and import, 7-day eviction, rate bucket, token refresh | an end-to-end upload of a recorded ride to both services from a fresh install; the Strava API review is submitted |
| **M5** Smart loops | all three strategies and the scorer, loop UI (distance slider, optional via, hills and surface), top three selectable and savable | "60 km via X" yields 3 candidates within 25 s; the best is within ±10 % of the target and under 15 % repeated segments in 8 of 10 fixture scenarios |
| **M6** Plus and AI | RevenueCat product and entitlement with a 7-day trial, paywall, restore, `PlusGate` wiring on Strava/RWGPS/AI/sharing, consent, assistant sheet, `IntentResolver`, descriptions, the Strava-source exclusion, link sharing (`POST /share` and the share page) | a sandbox purchase unlocks the assistant and the integrations; restore works after a reinstall without any login; a sentence produces a plotted route; a shared link opens the route in the app and previews in a browser |
| **M7** Store readiness | privacy manifests and strings, Play data safety and the location declaration with demo video, OSS licences screen, attribution audit, screenshots, icons, signing, `main` protection, CONTRIBUTING, the self-hosting guide | both store submissions are accepted for review |

Dependencies: M2 before M4, M1 before M5, M6 after M5.

## Verification

**On every pull request:** `dart format`, `flutter analyze`, unit tests for all
packages (GPX and FIT round trips, the geometry codec, BRouter parser fixtures,
the loop strategies and scorer, `IntentResolver`, the statistics and recovery
logic), widget tests with a fake `MapController` and a fake `RoutingBackend`
(planner, import preview, paywall gate, consent), golden tests only for
deterministic pure widgets (elevation chart, stats card, list tile), vitest for
the relay with mocked upstreams, and the `brouter_dart` parity levels as they
land.

**Nightly:** integration tests on an Android emulator (recording with mocked
location, the GPX open-with intent), a contract job against a BRouter container
with one small tile, and the `brouter_dart` corpus against two real tiles.

**Per milestone, by hand:** the "done when" column above, on a real Android
device and on an iPhone.

**In production:** a `GET /health` uptime check, the BRouter tiny-route
healthcheck, and an alert on the LLM daily budget breaker.

## Licences

Apache-2.0 for everything except `api/`, which is AGPL-3.0-only so that a
modified hosted relay has to publish its source; the HTTP boundary keeps the
app unaffected. `TRADEMARK.md` reserves the name, logo and icon: forks must
rebrand before publishing to a store and may not point at the official servers.
