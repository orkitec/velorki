# Self-hosting

You can run Velorki entirely on your own infrastructure. This page says what
you need and where the instructions are; it is a pointer, not the guide.

## What you need

**A routing server.** BRouter, with the rd5 segment tiles for the area you care
about. It is Java and runs in a 128–512 MB heap, so any small VPS is enough.
Disk is the real requirement: the planet set is 10–14 GB, so provision about
40 GB if you want the world, far less for one region. Without this, the app
cannot plan routes — unless you rely on on-device routing once that lands, in
which case you still need somewhere to serve the segment tiles from.

**The relay (`api/`), only if you want the paid-tier features.** It exists for
the Strava and RideWithGPS OAuth token exchange, the AI assistant and share
links. If you do not need those, skip it: set `VELORKI_API_URL` to an empty
string and the app hides the assistant, both integrations and link sharing.
Everything that runs on the phone — planning, loops, recording, GPX and FIT,
offline maps — keeps working.

To run the relay usefully you also need your own credentials: a Strava API
application, a RideWithGPS API key, an OpenAI-compatible LLM endpoint and key,
and a RevenueCat REST key (or `REVENUECAT_MODE=stub` to leave the endpoints
open).

**Nothing else.** There is no database of users, no sync service and no
account system to operate. The only state on the server side is the share-link
store and the segment tiles.

## The guide

**`deploy/README.md`** has the step-by-step instructions: the Docker Compose
file with Caddy, BRouter and the segment updater, the systemd alternative for
running BRouter without containers, the environment variables, and the first
segment sync (1–3 hours for the planet).

## Pointing a build at your servers

The app takes all its endpoints from `--dart-define` values, collected in
`AppConfig`. Builds pass them from a JSON file:

```
flutter run --dart-define-from-file=env/local.json
```

`env/local.json` is git-ignored; copy the committed example and change what you
need:

| Variable | Point it at |
|---|---|
| `VELORKI_BROUTER_URL` | your BRouter server |
| `VELORKI_API_URL` | your relay — **empty string** to build without it |
| `VELORKI_PHOTON_URL` | your Photon instance, or the public one |
| `VELORKI_MAP_STYLE_URL` | your MapLibre style (OpenFreeMap, or self-hosted PMTiles) |
| `VELORKI_MAP_STYLE_URL_DARK` | the style used in dark mode (default OpenFreeMap Dark) |
| `VELORKI_SEGMENTS_URL` | your rd5 segment mirror, for on-device routing tiles |
| `VELORKI_REVENUECAT_KEY_ANDROID` / `_IOS` | your RevenueCat public SDK keys |
| `VELORKI_STRAVA_CLIENT_ID` | your Strava application |
| `VELORKI_RWGPS_CLIENT_ID` | your RideWithGPS application |
| `VELORKI_OAUTH_SCHEME` | your own custom URL scheme for OAuth redirects |

Users can also override the server URLs at runtime under Settings → Advanced,
which is the quickest way to try your routing server against an existing build.

## If you publish your fork

`TRADEMARK.md` is binding here. The code is open source; the name, the logo and
the app icon are not. Before you publish a modified build to any store, website
or package repository you must:

- choose a different name and a different icon,
- remove the Velorki branding from the app, the store listing and the share
  pages,
- replace the server URLs in the build configuration with your own.

You may say your project is "based on Velorki" or "a fork of Velorki" and link
back here. You may not suggest that it is official or endorsed by Orkitec.

## The official servers are not for forks

Do not point a fork at `api.velorki.app`, the official routing server or the
official share links. They are sized and paid for the official app, the rate
limits assume it, and the trademark policy forbids it. Run your own — that is
what `deploy/` is for.
