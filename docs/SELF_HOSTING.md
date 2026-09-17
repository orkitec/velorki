# Self-hosting

## Nothing to host

**Velorki needs no backend.** The app routes on the phone: `brouter_dart` is a
Dart port of the BRouter engine and runs against rd5 segment tiles the rider
downloads for the area they ride, and those tiles bring their own place search
(`<TILE>.gaz`). Map tiles come from OpenFreeMap, and Photon is asked only when
the rider taps "Search online for …" or has no tiles at all — both directly
from the app.

The only thing you may want to serve yourself is the rd5 tiles, and that is a
static file host: any HTTPS directory with the `.rd5` files and a
`manifest.json` next to them works as `VELORKI_SEGMENTS_URL`.
`brouter/updater/sync.sh` writes that manifest — `formatVersion`,
`brouterVersion`, `source`, `generatedAt` and a `tiles` array of
`{tile, bytes, updatedAt}`.

- The mirror may also host offline search files, `<TILE>.gaz` next to the rd5
  (built by `tools/gazetteer/build.py`). `sync.sh` gives each such tile entry a
  `gazetteer` object; `tools/gazetteer/manifest.py <dir>` adds them after the fact.

The reference mirror is a GitHub Releases one, [orkitec/velorki-data][data],
which costs nothing to run; see its README, and the "rd5 tile mirror" item in
[OPEN_ITEMS.md](OPEN_ITEMS.md) for the caveat that a release holds at most
1,000 assets while a tile costs two of them (`.rd5` + `.gaz`), so a snapshot is
sharded across releases at 480 tiles each — three for the planet.

[data]: https://github.com/orkitec/velorki-data

## Optional: a BRouter server

Point `VELORKI_BROUTER_URL` at a BRouter server and the app routes through it
for any area the rider has not downloaded tiles for. `deploy/` runs one:

- `docker-compose.yml` — Caddy (TLS), BRouter, the segment updater, and the
  relay behind a compose profile;
- `Caddyfile` — `/brouter*` to BRouter, everything else to the relay;
- `.env.example`, `Makefile` and `bin/{route-test,sync-now,logs}`;
- `systemd/` — the Docker-free alternative, BRouter straight from a jar plus a
  sync service and timer.

BRouter runs at `-Xmx512M`, so 2–4 GB RAM is plenty; disk is the real
requirement. The planet is 1,142 tiles (~10 GB, provision 40 GB); Europe with
`SEGMENT_FILTER="E*_N4* E*_N5* W*_N5*"` is 224 tiles (~3.0 GB). The first sync
takes 1–3 hours for the planet. `deploy/README.md` is the step-by-step guide.

The same server also serves the tiles the app downloads: point
`VELORKI_SEGMENTS_URL` at the updater's `/segments4`.

## Optional: the relay

`api/` exists only for the Plus features: the Strava and RideWithGPS OAuth
token exchange, the AI assistant and share links. **Leave `VELORKI_API_URL`
empty and the app hides all three**; everything else keeps working.

It is a plain Node 22 process (`npm ci && npm run build && node dist/server.js`,
health at `/health`). To run it usefully you need your own credentials, in
`api/.env` (see `api/.env.example`):

| Key | For |
|---|---|
| `STRAVA_CLIENT_ID` / `_SECRET` | Strava sign-in; missing means `/oauth/strava/*` → 503 |
| `RWGPS_CLIENT_ID` / `_SECRET` | RideWithGPS sign-in |
| `OAUTH_REDIRECT_ALLOWLIST` | the exact redirect URIs your build uses |
| `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL` | any OpenAI-compatible endpoint, for the assistant |
| `REVENUECAT_SECRET_KEY` | entitlement checks; `REVENUECAT_MODE=stub` leaves the endpoints open, which is the right setting for a fork |
| `SHARE_DB_PATH` | the share-link SQLite file. It must be on a persistent volume, or every deploy breaks the links already handed out |

That file and the segment tiles are the only server-side state. There is no
user database, no sync service and no account system to operate.

## Pointing a build at your servers

Endpoints come from `--dart-define` values collected in `AppConfig`:

```
flutter run --dart-define-from-file=env/local.json
```

`env/local.json` is git-ignored; copy `env/example.json` and change what you
need.

| Variable | Point it at |
|---|---|
| `VELORKI_SEGMENTS_URL` | your rd5 tile host, for on-device routing |
| `VELORKI_BROUTER_URL` | your BRouter server — **empty** for on-device only |
| `VELORKI_API_URL` | your relay — **empty** to build without the Plus features |
| `VELORKI_PHOTON_URL` | your Photon instance, or the public one |
| `VELORKI_MAP_STYLE_URL` / `_DARK` | your MapLibre styles (OpenFreeMap, or self-hosted PMTiles) |
| `VELORKI_CYCLOSM_TILE_URL` | CyclOSM raster tiles for the optional overlay |
| `VELORKI_REVENUECAT_KEY_ANDROID` / `_IOS` | your RevenueCat public SDK keys |
| `VELORKI_STRAVA_CLIENT_ID` / `VELORKI_RWGPS_CLIENT_ID` | your applications |
| `VELORKI_OAUTH_SCHEME` | your own custom URL scheme for OAuth redirects |

Settings → Advanced overrides the server URLs at runtime, which is the quickest
way to try your routing server against an existing build.

## If you publish your fork

`TRADEMARK.md` is binding. The code is open source; the name, the logo and the
app icon are not. Before publishing a modified build anywhere you must choose a
different name and icon, remove the Velorki branding from the app, the store
listing and the share pages, and replace the server URLs with your own. You may
say your project is "based on Velorki" and link back here; you may not suggest
it is official or endorsed by Orkitec.

Do not point a fork at `api.velorki.com` or the official routing server: they
are sized and paid for the official app, and the trademark policy forbids it.
