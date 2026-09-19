# Velorki

Plan the ride, find the café, follow the turns, and do all of it where the
signal ends. Free, open source, built on OpenStreetMap.

Download a region once and the whole app works without a network: the map,
the routing, the place search and the spoken turns. No account, no ads, no
paywall on the ride itself, and no server in the loop unless you ask for one.
A Flutter app for iOS and Android. What it does:

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
- **Sensors, all optional.** Heart rate, cadence and power on every fix, from
  an Apple Watch (a companion app streams the pulse and shows the ride and
  the next turn on the wrist), from Bluetooth straps, speed and cadence
  sensors and power meters, or from Apple Health and Health Connect. Nothing
  asks for a permission until you switch a source on in Settings.
- **Files and services.** GPX and FIT import and export through the share
  sheet and open-with; Strava upload and route import; RideWithGPS routes and
  trips both ways; links to share a route.
- **Assistant.** A sentence like "40 km, mostly gravel, a café stop" becomes a
  plotted route, through a hosted model behind a relay that holds the key.
- Metric or imperial units; every string is localisable.

**Everything on the phone is free, for everyone, for good**: planning, loops,
offline maps and routing, search, navigation, recording, ride stats, GPX and
FIT files. The routing data and the search index are mirrored for you at no
charge. "Velorki Plus" is a small subscription only for the parts that need
our servers or a partner account: the Strava and RideWithGPS connections, the
assistant and link sharing. The code for all of it is here, so you can also
run your own and skip the subscription entirely.

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
| `app/` | the Flutter app and its pure-Dart packages (`app/packages/`) | AGPL-3.0-only |
| `web/` | velorki.com: the website and the relay (OAuth token exchange, AI relay, share links) in one Next.js app | AGPL-3.0-only |
| `brouter/` | routing profiles and the map-data updater for the BRouter routing server | AGPL-3.0-only |
| `deploy/` | self-hosting with Docker Compose or systemd | AGPL-3.0-only |
| `docs/` | architecture, self-hosting, privacy, store checklist | AGPL-3.0-only |
| `tools/` | the BRouter test oracle and the gazetteer builder | AGPL-3.0-only |

## Design in one paragraph

As much as possible runs on the device: the routes, the rides, the loop
generator, the place search and the routing itself. The server side is
optional — a stock BRouter routing server for areas without downloaded tiles,
and a small relay that only does what an open-source app cannot: keep the
Strava and RideWithGPS client secrets, call the language model, and store
shared links. No accounts, no cloud database. See `docs/ARCHITECTURE.md`.

## Building

`mise install` in the repository root installs Flutter, Java and Node at the
pinned versions. Then see `app/README.md` and `web/README.md`.

## Self-hosting

Velorki needs no backend. `docs/SELF_HOSTING.md` says what you can run yourself
anyway — a tile host, a routing server, the relay — and `deploy/README.md` is
the step-by-step for the last two. Forks must rebrand, see `TRADEMARK.md`.

## Licence

[AGPL-3.0](LICENSE). Modified versions have to flow back: whoever distributes
a changed app, or serves a changed relay or website, publishes the source
under the same licence, and keeps a "Based on Velorki (velorki.com) by
Orkitec" line in its about screen or website footer, see
`ADDITIONAL_TERMS.md`. The name, the logo and the app icon stay reserved, see
`TRADEMARK.md`.

## Credits

Map data © [OpenStreetMap](https://www.openstreetmap.org/copyright)
contributors, ODbL. Routing by [BRouter](https://brouter.de). Map tiles by
[OpenFreeMap](https://openfreemap.org). Online search by
[Photon](https://photon.komoot.io).
