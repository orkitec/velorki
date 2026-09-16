# Velorki

Plan the ride, find the café, follow the turns, and do all of it where the
signal ends. Free, open source, built on OpenStreetMap.

Download a region once and the whole app works without a network: the map,
the routing, the place search and the spoken turns. A Flutter app for iOS and
Android. What it does:

- **Routing on the phone.** A Dart port of the BRouter engine routes on
  downloaded 5°×5° tiles, with touring, road, gravel, MTB and direct
  profiles, up to three alternatives, elevation profile and surface
  statistics. A BRouter server is optional, for areas with no tiles.
- **Loops.** "A 60 km round trip from here via the lake": candidates are
  generated and scored on length, climbing, surface and repeated roads.
- **Place search offline.** Each routing tile brings a search index of its
  places, streets with house numbers, and points of interest: cafés, drinking
  water, toilets, repair stations, shelters, bike shops, campsites, hotels,
  passes, peaks, viewpoints, stations, landmarks. Typing "water" lists the
  nearest taps by distance; typos are corrected from the index itself. Online
  search through Photon is one tap away, and the first choice where no tile
  is downloaded.
- **Offline maps.** Vector map areas from OpenFreeMap saved per region, with
  the CyclOSM cycling overlay online.
- **Turn-by-turn.** Turn banner and spoken cues while recording along a route,
  re-routing when you leave it, compass or north-up follow modes.
- **Recording.** Runs in the background with a foreground notification on
  Android and a live activity on iOS; survives the app being killed; battery
  saver dims the screen and coarsens the GPS; ride pages with elevation,
  speed, splits and a speed-coloured track.
- **Files and services.** GPX and FIT import and export through the share
  sheet and open-with; Strava upload and route import; RideWithGPS routes and
  trips both ways; links to share a route.
- **Assistant.** A sentence like "40 km, mostly gravel, a café stop" becomes a
  plotted route, through a hosted model behind a relay that holds the key.
- Metric or imperial units; every string is localisable.

Everything that runs on your phone is free: planning, loops, recording, search,
files. "Velorki Plus" is a subscription for the parts that need our servers or
a partner account: the Strava and RideWithGPS connections, the assistant and
link sharing. The code for all of it is here, so you can also run your own.

## Status

Everything above is implemented and tested: unit and widget tests on every
push, emulator and simulator suites on Android 12, 15 and 16 and on iOS, and
the routing port reproduces the Java server byte for byte on a recorded
corpus. Nothing is in the stores yet.

Not yet done: the store accounts and partner API registrations, the relay and
the tile mirror deployment, and iOS release signing. `docs/OPEN_ITEMS.md` lists
every such item.

## Layout

| Directory | Contents | Licence |
|-----------|----------|---------|
| `app/` | the Flutter app and its pure-Dart packages (`app/packages/`) | Apache-2.0 |
| `api/` | the thin relay: OAuth token exchange, AI relay, share links | AGPL-3.0-only |
| `brouter/` | routing profiles and the map-data updater for the BRouter routing server | Apache-2.0 |
| `deploy/` | self-hosting with Docker Compose or systemd | Apache-2.0 |
| `docs/` | architecture, self-hosting, privacy, store checklist | Apache-2.0 |
| `tools/` | the BRouter test oracle and the gazetteer builder | Apache-2.0 |

## Design in one paragraph

As much as possible runs on the device: the routes, the rides, the loop
generator, the place search and the routing itself. The server side is
optional — a stock BRouter routing server for areas without downloaded tiles,
and a small relay that only does what an open-source app cannot: keep the
Strava and RideWithGPS client secrets, call the language model, and store
shared links. No accounts, no cloud database. See `docs/ARCHITECTURE.md`.

## Building

`mise install` in the repository root installs Flutter, Java and Node at the
pinned versions. Then see `app/README.md` and `api/README.md`.

## Self-hosting

Velorki needs no backend. `docs/SELF_HOSTING.md` says what you can run yourself
anyway — a tile host, a routing server, the relay — and `deploy/README.md` is
the step-by-step for the last two. Forks must rebrand, see `TRADEMARK.md`.

## Credits

Map data © [OpenStreetMap](https://www.openstreetmap.org/copyright)
contributors, ODbL. Routing by [BRouter](https://brouter.de). Map tiles by
[OpenFreeMap](https://openfreemap.org). Online search by
[Photon](https://photon.komoot.io).
