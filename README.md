# Velorki

Plan and ride bike routes. Free, open source, built on OpenStreetMap.

Velorki is a Flutter app for iOS and Android that plans bike routes with
bike-specific routing, generates loops ("a nice 60 km round trip from here via
the lake"), records your rides, and exchanges routes and rides with Strava,
RideWithGPS and anything that reads GPX or FIT files.

Everything that runs on your phone is free: planning, loops, recording, files.
"Velorki Plus" is a subscription for the parts that need our servers or a
partner account: the Strava and RideWithGPS connections, the AI assistant and
link sharing. The code for all of it is here, so you can also run your own.

## Status

All planned features are implemented and unit-tested; nothing is in the
stores yet. What exists today:

- Planning on OpenStreetMap with bike-specific routing, alternatives,
  elevation profile and surface statistics; smart loops with a scoring of
  candidates; GPX and FIT import and export; ride recording that survives the
  app being killed; Strava and RideWithGPS connections; a subscription with
  an AI assistant and link sharing.
- Routing runs either on a self-hosted BRouter server or **on the device**:
  `app/packages/brouter_dart` is a Dart port of the BRouter engine that
  reproduces the Java server byte for byte on a recorded corpus, with map
  tiles downloaded per region.
- Verified on the Android emulator: planning through a server, planning on
  the device after a tile download, recording and import screens.

Not yet done: the servers are not deployed, the store accounts and partner
API registrations are missing, and nothing has run on a real phone or on
iOS. `docs/OPEN_ITEMS.md` lists every such item.

## Layout

| Directory | Contents | Licence |
|-----------|----------|---------|
| `app/` | the Flutter app and its pure-Dart packages (`app/packages/`) | Apache-2.0 |
| `api/` | the thin relay: OAuth token exchange, AI relay, share links | AGPL-3.0-only |
| `brouter/` | routing profiles and the map-data updater for the BRouter routing server | Apache-2.0 |
| `deploy/` | self-hosting with Docker Compose or systemd | Apache-2.0 |
| `docs/` | architecture, privacy, store checklist | Apache-2.0 |

## Design in one paragraph

As much as possible runs on the device. The phone holds the routes, the rides,
the loop generator and, once the Dart port of BRouter lands, the routing
itself. The server side is a stock BRouter routing server and a small relay
that only does what an open-source app cannot: keep the Strava and RideWithGPS
client secrets, call the language model, and store shared links. No accounts,
no cloud database. See `docs/ARCHITECTURE.md`.

## Building

`mise install` in the repository root installs Flutter, Java and Node at the
pinned versions. Then see `app/README.md` and `api/README.md`.

## Self-hosting

`deploy/README.md` walks through running your own routing server and relay
with `docker compose up`. Forks must rebrand, see `TRADEMARK.md`.

## Credits

Map data © [OpenStreetMap](https://www.openstreetmap.org/copyright)
contributors, ODbL. Routing by [BRouter](https://brouter.de). Map tiles by
[OpenFreeMap](https://openfreemap.org). Search by
[Photon](https://photon.komoot.io).
