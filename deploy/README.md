# Self-hosting Velorki

Velorki is open source and its routing is plain [BRouter](https://github.com/abrensch/brouter).
This directory brings up your own stack: TLS, the routing engine, and a job that
mirrors the routing data.

> **brouter.de is a courtesy mirror, not a public API.**
> The segment tiles come from <https://brouter.de/brouter/segments4/>, which
> Arndt Brenschede provides for free. It is a *download* mirror for map data.
> Never point an app at `brouter.de` for live routing, and never let users hit
> it directly. Mirror the tiles once a week and route against your own server —
> that is exactly what the `brouter-updater` service here does.

---

## Contents

| Path | What it is |
|---|---|
| `docker-compose.yml` | The stack: `caddy`, `brouter`, `brouter-updater`, optional `api` |
| `Caddyfile` | TLS + routing: `/brouter*` → BRouter, everything else → the app |
| `web/` | The official deployment: Caddy config, Cloudflare and backup scripts, the deploy forced command — see [docs/DEPLOY_WEB.md](../docs/DEPLOY_WEB.md) |
| `.env.example` | Configuration template |
| `Makefile`, `bin/` | `sync-now`, `logs`, `route-test` helpers |
| `systemd/` | Docker-free alternative: run BRouter straight from a jar |
| `../brouter/` | BRouter image, segment updater, pinned routing profiles |

---

## 1. Prerequisites

* A VPS with **Docker** and the Compose plugin (Docker Engine 20.10+).
* **2–4 GB RAM.** BRouter runs at `-Xmx512M` and is capped at 1 GB; the rest is
  for Caddy, the OS page cache (which matters a lot — segment lookups are
  mmap-ish random reads) and, optionally, the API.
* **Disk:**

  | Coverage | Tiles | Download | Recommended disk |
  |---|---:|---:|---:|
  | Whole planet (`SEGMENT_FILTER=*`) | 1142 | ~10 GB | **40 GB** |
  | Europe (`E*_N4* E*_N5* W*_N5*`) | 224 | ~3.0 GB | **~5 GB** |

  (Measured against the mirror on 2026-09-12. Tiles grow over time, and an
  update briefly needs room for the new copy beside the old one, hence the
  headroom.)
* A **domain** with an `A`/`AAAA` record already pointing at the VPS. Caddy
  needs ports 80 and 443 reachable to get a Let's Encrypt certificate.

## 2. Configure

```sh
cd deploy
cp .env.example .env
$EDITOR .env          # at minimum: DOMAIN and ACME_EMAIL
```

## 3. Start

```sh
docker compose up -d          # or: make up
```

This builds the BRouter image from the pinned upstream tag (a few minutes —
it compiles the upstream repo with Gradle) and starts three containers:

* `velorki-caddy` — ports 80/443
* `velorki-brouter` — internal only, port 17777, never published to the host
* `velorki-brouter-updater` — starts mirroring tiles immediately

### First sync

**The first sync takes 1–3 hours for the planet** (~10 GB), or roughly 20–40
minutes for Europe. Watch it:

```sh
make logs S=brouter-updater
```

You get one line per tile:

```
2026-09-12T16:54:50Z [sync] E5_N45 ok 12.1MB
2026-09-12T16:54:51Z [sync] E5_N50 skip unchanged (8.4MB)
```

**`brouter` reports `unhealthy` until the tile covering Zurich (`E5_N45`) has
arrived** — its healthcheck is a real route. That is expected on a fresh box;
nothing restarts because of it. Routing requests for an un-mirrored area return
HTTP 400 with a BRouter error message, not 502.

The sync is safe to interrupt. Downloads land in `<tile>.rd5.part` and are only
renamed into place once their size matches the mirror's index, so `docker
compose down` mid-sync loses at most one tile, and the next pass resumes.

### Only Europe

Cuts disk and first-sync time by two thirds:

```sh
# in .env
SEGMENT_FILTER=E*_N4* E*_N5* W*_N5*
```

```sh
docker compose up -d brouter-updater
make sync-now
```

`SEGMENT_FILTER` is a space-separated list of globs matched against tile names
(`E5_N45`, the `.rd5` implied). Tiles are 5°×5°, named by the longitude/latitude
of their **south-west corner**: `E5_N45` covers 5–10°E, 45–50°N. Some more
examples:

| Goal | Filter |
|---|---|
| Everything | `*` |
| Europe | `E*_N4* E*_N5* W*_N5*` |
| Europe incl. Iberia/Ireland | `E*_N4* E*_N5* W*_N4* W*_N5*` |
| German-speaking Alps only | `E5_N45 E10_N45 E5_N50 E10_N50` |
| North America | `W*_N3* W*_N4* W*_N5* W*_N6*` |

Narrowing the filter does **not** delete tiles you already have; remove those by
hand from the volume if you want the space back.

## 4. Verify

```sh
make route-test           # or: bin/route-test
```

It requests a real route through Caddy — the same path a Velorki client takes —
and prints the distance:

```
==> GET https://velorki.example.com/brouter?lonlats=8.5,47.4|8.51,47.41&profile=trekking&...
OK: 1489 m, 331 s, profile=trekking
```

Test another profile or area:

```sh
bin/route-test gravel '13.4,52.5|13.42,52.52'
```

Other checks:

```sh
make health                       # container status
make logs S=brouter               # routing engine log
docker compose exec brouter-updater cat /segments4/manifest.json | head -20
```

`manifest.json` is written at the end of every sync pass and describes what is
actually on disk:

```json
{
  "formatVersion": "11.2",
  "brouterVersion": "v1.7.10",
  "source": "https://brouter.de/brouter/segments4/",
  "segmentFilter": "E*_N4* E*_N5* W*_N5*",
  "generatedAt": "2026-09-12T16:54:51Z",
  "tiles": [
    { "tile": "E0_N20", "bytes": 524310, "updatedAt": "2026-09-11T23:03:00Z" }
  ],
  "tileCount": 224,
  "totalBytes": 3198765432
}
```

`formatVersion` is the lookup version pair from `lookups.dat`
(`---lookupversion:11` / `---minorversion:2`). BRouter refuses to read a segment
whose version does not match the `lookups.dat` it started with, so this is the
number to compare if routing suddenly fails after an upgrade. Per-tile `sha256`
is omitted by default because hashing ~10 GB every pass is slow and the size
check against the mirror index already catches truncation — set
`MANIFEST_SHA256=1` if you want it. A tile with an offline-search file
(`<TILE>.gaz`, from `tools/gazetteer`) next to its rd5 also gets a `gazetteer`
object of `bytes`, `sha256` and `updatedAt`; that one is always hashed.

## 5. Keeping data fresh

`brouter-updater` re-syncs every `SYNC_INTERVAL` (default `7d`). brouter.de
rebuilds its tiles nightly, but weekly is plenty for routing and is kinder to a
volunteer-run mirror. Unchanged tiles cost one conditional request each
(`If-Modified-Since`), not a download, so a routine pass moves very little data.

To sync right now:

```sh
make sync-now
```

That runs one extra pass inside the running container; a lock makes it a no-op
if the periodic pass is already running.

## 6. Updating BRouter

```sh
# 1. bump the tag in .env
BROUTER_VERSION=v1.7.11

# 2. re-copy the matching profiles (see ../brouter/profiles/README.md)
# 3. rebuild
make update-brouter
```

Keep `../brouter/profiles/lookups.dat` and `BROUTER_VERSION` on the *same*
upstream tag. If the lookup version changes between releases, the mirrored
segments must be re-downloaded too — delete the volume and re-sync.

### Velorki's profile variants

`../brouter/profiles` also carries Velorki's own `velorki-*.brf` variants,
which keep a bike off one-way streets ridden the wrong way and off pavements
(see its README). A server deployed from this repo has them; the app only
asks a server for them when it is built with `VELORKI_BROUTER_VARIANTS=1`.
Without that define it asks for the upstream profiles, so a server deployed
before the variants existed keeps answering, with upstream behaviour. After
redeploying with the current `../brouter/profiles`, build the app with the
define to switch the server's routes to the variants; the on-device engine
always uses them.

## 7. Running the website and API

`web/` is one Next.js app that serves both the website and the relay API,
separated by the Host header. There are two ways to run it.

### a) With Orkify, as a plain Node process — what the official VPS does

The official Velorki deployment does **not** run it in Docker. Orkify deploys
`web/` from the monorepo as an ordinary Node cluster on `velorki.com` and
`api.velorki.com`, behind Caddy and Cloudflare.

**[docs/DEPLOY_WEB.md](../docs/DEPLOY_WEB.md) is the complete runbook** — the
VPS, Node, Orkify, Caddy with a Cloudflare Origin CA certificate, the Cloudflare
zone, the deploy workflow, backups and operations. The pieces it installs live
in `deploy/web/`: `Caddyfile`, `cloudflare-ips.sh`, `backup-sqlite.sh`,
`velorki-deploy` and `velorki-web.env.example`.

That Caddy config replaces this directory's `Caddyfile`, which only knows about
BRouter and a single domain. If you run BRouter on the same box, copy the
`/brouter*` block out of `deploy/Caddyfile` into `deploy/web/Caddyfile`.

### b) In compose — for a self-contained box

The `api` service sits behind a compose **profile** so it stays out of the way
in mode (a). Start it explicitly:

```sh
docker compose --profile api up -d      # or: make up-api
```

It builds `../web` with `web/Dockerfile` by default (Node 22 build stage,
distroless runtime, `.next/standalone`). To use the prebuilt image instead,
follow the comment in `docker-compose.yml`: comment out the two `build:` lines,
uncomment `image: ghcr.io/orkitec/velorki-web:${API_TAG:-latest}`, set `API_TAG`
in `.env`, and `docker compose --profile api up -d`.

Note that `api` reads **all** of `.env` (`env_file`), so fill in the API section
there in this mode; `SITE_HOST` and `API_HOST` both default to `DOMAIN`, which
is right when one Caddy site block serves everything. The share database is the
`api_data` volume at `/var/lib/velorki`. `make logs` and `make down` already
include the profile.

## 8. Without Docker

`systemd/` runs BRouter straight from the official release jar — useful on a box
that already has a web server:

```sh
sudo systemd/install-systemd.sh        # uses ../brouter/UPSTREAM_VERSION
```

It creates a `brouter` system user, installs the pinned release jar and this
repo's profiles into `/opt/brouter`, and enables:

* `brouter.service` — the routing server on 127.0.0.1:17777, `-Xmx512M`
* `brouter-sync.timer` → `brouter-sync.service` — the same `sync.sh`, weekly

Set the coverage in `/etc/systemd/system/brouter-sync.service`
(`Environment=SEGMENT_FILTER=...`) **before** the first
`systemctl start brouter-sync.service`. You still need your own TLS terminator
in front; copy the `/brouter*` block out of the `Caddyfile`.

## 9. Backups

Only three things are not reproducible from this repo:

| What | Why |
|---|---|
| `deploy/.env` | Your secrets. Not in git. |
| `caddy_data` volume | TLS certificates and the ACME account key. Losing it means re-issuing certs and burning Let's Encrypt rate limit. |
| `api_data` volume | Share links (`SHARE_DB_PATH`). |

```sh
docker run --rm \
  -v velorki_caddy_data:/caddy_data:ro \
  -v velorki_api_data:/api_data:ro \
  -v "$PWD:/backup" alpine \
  tar czf /backup/velorki-backup-$(date +%F).tar.gz /caddy_data /api_data
cp .env "velorki-env-$(date +%F).bak"
```

**Do not back up `brouter_segments`.** It is 10 GB of data you can re-download,
and a stale copy is worse than a fresh sync.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `brouter` stuck `unhealthy`, `route-test` gives 400 | Tile `E5_N45` not mirrored yet. Check `make logs S=brouter-updater`. |
| All routes 400 right after a version bump | `lookups.dat` and the segments disagree. Re-copy profiles at the pinned tag, re-sync. |
| `route-test` gives 502 | `brouter` (or `api`) is not running: `make health`. |
| Caddy cannot get a certificate | DNS does not point here yet, or 80/443 blocked upstream. `make logs S=caddy`. |
| Sync logs `FAIL size mismatch` | Tile changed mid-download, i.e. the nightly rebuild overlapped. Harmless; the next pass picks it up. |
| `WARNING SEGMENT_FILTER=... matched no tile` | Typo in the filter. Tile names look like `E5_N45`, no `.rd5`. |

## Licensing

BRouter and its profiles are MIT licensed (Arndt Brenschede and contributors) —
see `../brouter/profiles/README.md`. Segment data is derived from
OpenStreetMap, © OpenStreetMap contributors, [ODbL](https://www.openstreetmap.org/copyright).
If you expose routing publicly you must carry that attribution.
