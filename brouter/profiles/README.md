# BRouter routing profiles

Routing profiles shipped with Velorki's self-hosted BRouter. They are mounted
read-only at `/profiles2` inside the `brouter` container.

## Origin

| Item | Value |
|---|---|
| Upstream | <https://github.com/abrensch/brouter> |
| Pinned tag | `v1.7.10` (see `../UPSTREAM_VERSION`) |
| Source path | `misc/profiles2/` in the upstream repo |
| License | MIT — see <https://github.com/abrensch/brouter/blob/v1.7.10/LICENSE> |
| Fetched | 2026-09-12 |

Every file below is **byte-identical to the corresponding file in the official
`brouter-1.7.10.zip` release artifact**.

| File | Bytes | How it was obtained |
|---|---:|---|
| `lookups.dat` | 31604 | `misc/profiles2/lookups.dat` @ `v1.7.10` |
| `trekking.brf` | 17852 | `misc/profiles2/trekking.brf` @ `v1.7.10` |
| `fastbike.brf` | 15984 | `misc/profiles2/fastbike.brf` @ `v1.7.10` |
| `fastbike-lowtraffic.brf` | 15975 | **generated** — see note below |
| `fastbike-verylowtraffic.brf` | 15462 | `misc/profiles2/fastbike-verylowtraffic.brf` @ `v1.7.10` |
| `gravel.brf` | 19121 | `misc/profiles2/gravel.brf` @ `v1.7.10` |
| `mtb.brf` | 28998 | `misc/profiles2/mtb.brf` @ `v1.7.10` |
| `shortest.brf` | 5528 | `misc/profiles2/shortest.brf` @ `v1.7.10` |

### Note on `fastbike-lowtraffic.brf`

This file does **not** exist in the upstream git tree. Upstream generates it at
release time from `fastbike.brf` with `misc/scripts/generate_profile_variants.sh`:

```sh
sed -e "s/^assign[[:space:]]\+consider_traffic.*\(#.*\)/assign consider_traffic = true \1/" \
    fastbike.brf > fastbike-lowtraffic.brf
```

We ran exactly that command and confirmed the result is byte-identical
(15975 bytes) to `profiles2/fastbike-lowtraffic.brf` inside `brouter-1.7.10.zip`.
It differs from `fastbike.brf` in one line only (`consider_traffic`).

### Velorki's own variants

`velorki-trekking.brf`, `velorki-fastbike.brf`, `velorki-gravel.brf` and
`velorki-mtb.brf` are **not upstream files**. Each is the upstream profile of
the same name with a short header and a few lines changed, every one marked
`velorki:`: riding the wrong way down a small one-way street costs about as
much as on a primary road (upstream treats it as pushing, +4), and a pavement
a bicycle is not let onto (`footway=sidewalk` without `bicycle=yes`) costs
about three times what upstream charges. They are what the app asks the
router for (`RouteProfile.engineName`); saved routes still store the upstream
name. The upstream files beside them stay byte-identical, so the oracle
corpus, which only uses those, is untouched. `app/assets/brouter/profiles/`
carries the same files for the on-device engine, which always uses them. A
routing server is asked for them only when the app is built with
`VELORKI_BROUTER_VARIANTS=1`; otherwise it gets the upstream names, so a
server deployed before the variants existed keeps working. Redeploying a
server with this directory and building with the define switches its routes
to the variants (`../../deploy/README.md`, "Velorki's profile variants").

### Note on file names

Two names differ from what you might expect:

* There is no `MTB.brf`; upstream's file is lowercase **`mtb.brf`**.
* `fastbike-verylowtraffic.brf` (in git) and `fastbike-lowtraffic.brf`
  (generated) are two different profiles. Both are shipped.

### No per-file license headers

The `.brf` files carry a descriptive comment header but **no MIT header** — the
MIT license applies through the repository `LICENSE`, which this README records.
The files are shipped verbatim; no header was added or removed.

## `lookups.dat` and the segment format

`lookups.dat` declares the tag-lookup version:

```
---lookupversion:11
---minorversion:2
```

BRouter refuses to open an `.rd5` segment whose header version does not match the
`lookups.dat` it started with (`lookup version mismatch (old rd5?)`). So this
pair is effectively the segment format version, and it is what the segment
mirror records as `formatVersion` in `/segments4/manifest.json`.

**If you bump `BROUTER_VERSION`, re-copy these files from the same tag.** A
mismatch between `lookups.dat` and the mirrored segments breaks all routing.

## Updating

```sh
TAG=v1.7.11
BASE=https://raw.githubusercontent.com/abrensch/brouter/$TAG/misc/profiles2
for f in lookups.dat trekking.brf fastbike.brf fastbike-verylowtraffic.brf \
         gravel.brf mtb.brf shortest.brf; do
  curl -fsSL -o "$f" "$BASE/$f"
done
sed -e "s/^assign[[:space:]]\+consider_traffic.*\(#.*\)/assign consider_traffic = true \1/" \
    fastbike.brf > fastbike-lowtraffic.brf
echo "$TAG" > ../UPSTREAM_VERSION
```

Then update `BROUTER_VERSION` in `deploy/.env` and run `make update-brouter`.
