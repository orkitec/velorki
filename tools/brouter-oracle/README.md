# BRouter test oracle (track R0)

The `app/packages/brouter_dart` port has to behave exactly like upstream
BRouter. This directory is the reference it is measured against: it runs the
**real BRouter 1.7.10** locally against a small, pinned set of real `.rd5`
segment tiles, records a corpus of routing requests together with their full
responses, and can dump the decoded contents of rd5 micro-caches and of profile
evaluations as JSON using the upstream Java classes.

Everything here is read-only with respect to the rest of the repository. In
particular the routing profiles are **used in place** from `brouter/profiles/`;
they are never copied, so the oracle and the deployed server can never drift
apart.

## Parity levels

The plan defines three levels of parity for the Dart port. Each has a tool here:

| Level | What has to match | Tool |
|---|---|---|
| **L1** | byte-identical `util`/`codec` round trips and rd5 decoding | `dump/run_dump.sh dump-microcache` — decoded nodes, links, way/node tag bitmaps (as hex), geometry bytes and transfer nodes for one micro-cache |
| **L2** | profile evaluation bit-identical (the plan said 1e-6; the port meets the stricter target) | `dump/run_dump.sh eval-profile` — every cost variable a `.brf` produces for a list of tag sets, forward and reverse; `way-tags` builds the corpus from the tiles |
| **L3** | identical coordinates, length, ascent and messages for 200+ routing cases | `gen_corpus.py` / `run_corpus.py` / `check_corpus.py` plus `corpus/` |

The Dart port reproduces the same JSON and the same numbers; the golden tests in
`app/packages/brouter_dart/test/` read `corpus/` and `dump/samples/` directly.

## Layout

```
tools/brouter-oracle/
├── common.sh            shared paths, the pinned version, the Java 17 lookup
├── fetch.sh             download the release zip; stage the rd5 tiles into .cache/
├── serve.sh / stop.sh   run the upstream RouteServer on port 17777
├── tiles/               the committed rd5 fixtures (4.2 MB) + their README
├── tiles.txt            which tiles, their size, and where they came from
├── tiles.sha256         the exact data snapshot the corpus is bound to
├── oracle_common.py     stdlib-only helpers shared by the three corpus scripts
├── gen_corpus.py        deterministic request generation  -> corpus/requests.json
├── run_corpus.py        record responses                  -> corpus/responses/, corpus/index.json
├── check_corpus.py      replay and compare                -> exit 1 + a diff file
├── corpus/
│   ├── requests.json    200 cases: id, kind, region, profile, waypoints, query
│   ├── index.json       per case: status, track-length, ascends, cost, coords, body sha256
│   └── responses/       the verbatim geojson bodies (4.6 MB)
├── dump/
│   ├── Dump.java        single-file Java tool on the upstream public API
│   ├── run_dump.sh      compiles it once into .cache/ and runs it
│   └── samples/         tags.txt, tags-large.txt (the way-tag corpus), node-tags-large.txt, tags-units.txt
│                        + the JSON two profiles and two tiles produce
└── .cache/              everything downloaded or built (git-ignored)
```

## Requirements

Java 17, Python 3 (stdlib only), `curl`, `unzip`. No Docker, no Gradle, no pip
packages. `common.sh` picks up `JAVA_HOME` if set, otherwise the mise
`java@temurin-17.0.20+101` install, otherwise whatever `java` is on `PATH`.

## Quick start

```sh
cd tools/brouter-oracle
./fetch.sh          # ~7 MB: the release zip. The two rd5 tiles are committed
                    # in tiles/ and are only copied into .cache/segments4
                    # (./fetch.sh --tiles-only skips the zip, as CI does:
                    #  that run touches no network at all)
./serve.sh          # RouteServer on 127.0.0.1:17777
python3 check_corpus.py
./stop.sh
```

`check_corpus.py` exits 0 when all 200 cases reproduce, and 1 otherwise after
writing a per-case diff to `.cache/check-diff.txt`.

## The pinned upstream

`brouter/UPSTREAM_VERSION` is the single source of truth (`v1.7.10`).

* Release asset: `brouter-1.7.10.zip`, resolved through the GitHub releases API
  (`/repos/abrensch/brouter/releases/tags/v1.7.10`) and downloaded from
  `https://github.com/abrensch/brouter/releases/download/v1.7.10/brouter-1.7.10.zip`
  — 6 724 983 bytes,
  sha256 `023fec3ba997758e8cd7ab9e1bae52e962af3f00b57683e3de86b84ffad01532`.
* The server jar inside the zip is **`brouter-1.7.10/brouter-1.7.10-all.jar`**.
  There is no `brouter-server/build/libs/` in the release artifact; that path
  only exists in a Gradle build tree. The jar's `Main-Class` is
  `btools.server.BRouter`, so `RouteServer` has to be named explicitly.

The exact server command line `serve.sh` runs:

```sh
java -Xmx256M -DmaxRunningTime=0 \
  -cp .cache/zip/brouter-1.7.10/brouter-1.7.10-all.jar \
  btools.server.RouteServer \
  .cache/segments4 ../../brouter/profiles .cache/customprofiles 17777 4
```

(`RouteServer` takes `<segmentdir> <profiledir> <customprofiledir> <port>
<maxthreads> [bindaddress]`.)

## Determinism

BRouter's search is deterministic, but three things in 1.7.10 are not, and the
harness closes all three:

1. **The routing timeout.** `RouteServer.getMaxRunningTime()` defaults to 60 s
   and `RoutingEngine` aborts a search that exceeds it, so a slow or loaded
   machine can change the answer. `-DmaxRunningTime=0` disables it: every
   timeout check in `RoutingEngine` is guarded by `if (maxRunningTime > 0)`.
   (The one place where 0 changes behaviour rather than removing a deadline is
   the "early exit for a close recalc" branch, which only runs for incremental
   recalculation against a previous track. `RouteServer` builds a fresh
   `RoutingEngine` per request with no `outfileBase`, so that branch is
   unreachable here.)
2. **Round trips without a direction.** With `engineMode=4`,
   `RoutingEngine.doRoundTrip()` falls back to `getRandomDirectionFromData()`
   when no start direction is given, and that ends in `Math.random()`. Every
   round-trip case in the corpus therefore passes an explicit `direction=<deg>`.
3. **Response encoding.** The server gzips when the client advertises it, so the
   recorded body hash would depend on the HTTP client. All requests are sent
   with `Accept-Encoding: identity`.

Proven, not assumed: the full generate → record → check cycle was run three
times, the third time with a fresh JVM and a freshly re-staged segments dir. All 202
artefacts (`requests.json`, `index.json`, 200 response bodies) were byte
identical every time, and `check_corpus.py` reported 0 of 200 mismatched.

## The tiles

Chosen from the live index at <https://brouter.de/brouter/segments4/>, listing
timestamp **12-Sep-2026 01:03** (CET map snapshot time; the directory itself was
last written 12-Sep-2026 03:13). That snapshot is now **frozen in the repo**:
both files are committed under `tiles/` and `fetch.sh` only copies them, never
downloads them. See "The corpus is bound to a data snapshot" and
`tiles/README.md`. The rule was: the two smallest tiles that still
contain a real, connected road network. Both are island tiles, so the network is
fully inside the tile and no neighbouring segment is ever needed.

| Tile | Area | Bytes | sha256 |
|---|---|---:|---|
| `W20_N30` | Madeira and Porto Santo | 1 527 283 | `1e18289694cc451ae1761a67ed732081b41c5d0b6b570a3d144f9e5bc6fa6a4b` |
| `W25_N60` | SW Iceland (Reykjavík, Reykjanes) | 2 655 536 | `824ef377d3459e92f974f0ce93e880df82a572ce38d5789cc5c347450beb3f6f` |

Both were verified to route before anything was recorded, for example
Funchal → Machico (25 317 m, 814 m filtered ascend) and
Reykjavík → Hafnarfjörður (11 872 m).

Candidates that were rejected: Malta sits in `E10_N35`, which also carries
Sicily and eastern Tunisia and is far over 16 MB; the Faroes tile `W10_N60` is
under 1 MB and too sparse; the Azores tile `W30_N35` (1.6 MB) is a set of
mutually unreachable islands.

### The corpus is bound to a data snapshot

**brouter.de rebuilds `segments4` every night.** The recorded responses, and the
`brouter_dart` golden vectors, are only valid for the two checksums in
`tiles.sha256`. As soon as upstream regenerates a tile the geometry can change
for perfectly legitimate reasons (an OSM edit), and a mismatch then says nothing
about the Dart port.

So the tiles are **not** fetched from brouter.de, or from anywhere else. The
exact bytes the fixtures were recorded against are committed in this repo:

> `tools/brouter-oracle/tiles/W20_N30.rd5` and `W25_N60.rd5` — 4.2 MB together,
> plain files, no Git LFS. `tiles/README.md` carries the snapshot date, the
> checksums and the ODbL attribution.

`fetch.sh` copies them into `.cache/segments4`, checking each against
`tiles.sha256` first, and never touches the network for them: `./fetch.sh
--tiles-only` is fully offline, so the parity suite works on a laptop on a train
and in CI without a single download. `SEGMENTS_BASE_URL` (env
`BROUTER_SEGMENTS_BASE_URL`, default `$UPSTREAM_SEGMENTS_URL`) is only consulted
for a tile that `tiles.txt` lists but `tiles/` does not carry — the re-recording
path below. `BROUTER_TILES_DIR` points the fixtures directory somewhere else and
exists for the tests of `fetch.sh` itself.

**On failure `fetch.sh` gets the tiles out of the way.** It exits **1** when a
listed tile is neither committed nor downloadable and **3** when the checksums
do not match (either a committed fixture that no longer matches `tiles.sha256`,
or wrong bytes already in `.cache/segments4`), and in both cases it moves the
files into `.cache/segments4-bad/`. That matters: the `brouter_dart` tests fall
back to `.cache/segments4` when `BROUTER_SEGMENTS_DIR` is unset, so tiles left
behind after a failed fetch would be picked up anyway and the suite would report
parity diffs that are really just the wrong data. With the directory emptied,
`tilesMissing` reports them as absent and the tile-backed tests skip.

CI does **not** skip, though: it runs `./fetch.sh --tiles-only` bare, so any
failure here turns the job red. A silently skipped parity suite is worse than a
red run.

### Bumping to a newer upstream snapshot

Regenerating is a deliberate act. Never regenerate to make a red `brouter_dart`
test go green — first decide whether the tiles changed or the port did.

```sh
cd tools/brouter-oracle

# 1. get the new tiles from upstream and make them the committed fixtures.
#    With tiles/ empty, fetch.sh falls back to $UPSTREAM_SEGMENTS_URL; it then
#    exits 3 and quarantines what it downloaded, because those bytes are not
#    the ones tiles.sha256 pins. Moving them into tiles/ by hand is the point
#    at which you confirm you mean to re-bind everything.
rm -rf .cache/segments4 && rm -f tiles/*.rd5
./fetch.sh --tiles-only || true
mv .cache/segments4-bad/*.rd5 tiles/

# 2. re-pin the hashes against the new fixtures
(cd tiles && sha256sum *.rd5) > tiles.sha256
./fetch.sh --tiles-only      # must be green now, straight out of tiles/
# update the byte sizes and the index timestamp in tiles.txt, in tiles/README.md
# and in this README

# 3. re-record everything that is bound to the tiles
./serve.sh
python3 gen_corpus.py        # re-samples and re-validates every case
python3 run_corpus.py        # re-records corpus/responses/ and corpus/index.json
python3 check_corpus.py      # must be green immediately
./stop.sh
#    and the brouter_dart mapaccess vectors (see that package's README)

# 4. commit tiles/, corpus/, the regenerated vectors, tiles.sha256 and
#    tiles.txt in ONE commit
```

## The corpus

200 cases, 100 per region, generated by `gen_corpus.py` from the fixed seed
`20260912`. Anchor points are not random coordinates: they are sampled from the
geometry of a handful of fixed "backbone" routes, so every waypoint sits on the
real road network instead of in the Atlantic. Every candidate is then issued
once and only kept if it really routes.

| Kind | Cases | What it exercises |
|---|---:|---|
| `pair` | 120 | 6 profiles × `alternativeidx` 0–3, 5 cases each |
| `triple` | 40 | a via point, cycling profiles and alternatives |
| `nogo` | 24 | `nogos=<lon>,<lat>,<radius-m>` on the midpoint, radii 120/200/350 m |
| `roundtrip` | 16 | `engineMode=4` with `roundTripDistance`, `direction`, `roundTripPoints=5` |

Profiles: `trekking` 34, `fastbike` 34, `fastbike-lowtraffic` 34, `gravel` 34,
`mtb` 32, `shortest` 32. Track lengths 894 m – 20 313 m, mean 4 994 m, 999 km
and 47 160 coordinates in total. `corpus/responses/` is 4.61 MB, the whole
directory 5.3 MB — comfortably inside the ~15 MB budget, so the responses are
committed.

Round-trip parameter names are the real ones in 1.7.10, taken from
`RoutingParamCollector.setParams()`: `roundTripDistance` (an Integer, the
**radius in metres to the generated circle points**, not the total length),
`roundTripDirectionAdd`, `roundTripPoints` (clamped to 3–20, default 5), and the
start bearing via `direction` (or `heading`, which additionally sets
`forceUseStartDirection`). There is no `roundTripStartDirection`.

`corpus/index.json` records, per case: `status`, `track_length`,
`filtered_ascend`, `plain_ascend`, `cost`, `coordinates`, `messages`, `bytes`
and the `sha256` of the body. `check_corpus.py` compares all of them exactly.

## The Java dump tool

`dump/Dump.java` is a single file compiled with
`javac -cp <brouter-all.jar>`; `dump/run_dump.sh` compiles it into `.cache/` on
first use and runs it. A bare tile name resolves inside `.cache/segments4`, a
bare profile name inside `brouter/profiles`.

```sh
./dump/run_dump.sh dump-microcache W20_N30 -16.9085 32.6485 --limit 20 --geometry
./dump/run_dump.sh dump-microcache W20_N30 -16.9085 32.6485 --profile trekking

# L1 vectors and raw caches for the Dart port (app/packages/brouter_dart):
./dump/run_dump.sh codec-vectors <out-dir>                       # JSON test vectors for util + codec classes
./dump/run_dump.sh microcache-bytes W20_N30 -16.9085 32.6485 <out.bin>   # raw encoded micro-cache
./dump/run_dump.sh microcache-listing W20_N30 -16.9085 32.6485   # node/link listing the Dart decoder must reproduce

# R2 (mapaccess) parity:
./dump/run_dump.sh osmfile-index W20_N30                                   # header, file index, per-cell sizes and crcs
./dump/run_dump.sh nodes-cache-walk -16.92 32.65 -16.77 32.72 --steps 400  # NodesCache walk mirroring RoutingEngine

# R3 (expressions) parity:
./dump/run_dump.sh way-tags W20_N30 > dump/samples/tags-large.txt          # every distinct way tag set of a tile
./dump/run_dump.sh eval-profile trekking dump/samples/tags-large.txt --compact --bits   # float-bit-exact variable dumps
./dump/run_dump.sh math-vectors <out.json>                                  # JVM float parse/format/arith vectors
./dump/run_dump.sh nodes-cache-walk -16.92 32.65 -16.77 32.72 --profile trekking

# R4 (core) parity: the Dart engine replays corpus/requests.json and must reproduce
# corpus/responses/*.geojson byte for byte (app/packages/brouter_dart/test/corpus_parity_test.dart).
./dump/run_dump.sh core-vectors <out.json>                                  # JVM exp/DecimalFormat/Double.toString vectors
./dump/run_dump.sh eval-profile trekking dump/samples/tags.txt

# R3 (expressions) parity:
./dump/run_dump.sh way-tags W20_N30 > way-W20_N30.txt                      # every distinct way tag string of the tile
./dump/run_dump.sh way-tags W20_N30 --kind node                            # ... node tag strings
./dump/run_dump.sh eval-profile trekking dump/samples/tags-large.txt --compact --encode   # float bits, de-duplicated
./dump/run_dump.sh eval-profile trekking dump/samples/tags.txt --bits      # float bits per case
./dump/run_dump.sh eval-profile trekking dump/samples/node-tags-large.txt --compact --context node --way-tags "highway=residential surface=asphalt"
./dump/run_dump.sh nodes-cache-walk -16.92 32.65 -16.77 32.72 --steps 400 --profile trekking   # the real profile
./dump/run_dump.sh math-vectors <out-dir>                                  # JVM float semantics as bit patterns
```

**`dump-microcache <tile> <lon> <lat>`** opens the rd5 through
`btools.mapaccess.PhysicalFile`, picks the `OsmFile` for the containing degree
square, decodes the one micro-cache covering the position with
`OsmFile.createMicroCache(...)`, then walks it exactly the way
`btools.router.AreaReader` does: `MicroCache.getIdForIndex(i)` →
`MicroCache.getAndClear(id)` → `OsmNode.parseNodeBody(...)`. For every node it
prints the 64-bit id, `ilon`/`ilat` and the decimal position, `selev`, the node
description bitmap, turn restrictions, and every link with its target,
direction, description bitmap (hex), the decoded way tag string from
`BExpressionContextWay.getKeyValueDescription(...)`, the raw geometry bytes and
— with `--geometry` — the transfer nodes from `GeometryDecoder`.

Without `--profile` no `TagValueValidator` is passed, so the dump is the raw
decoded micro-cache: that is the L1 target. With `--profile` the profile acts as
the validator, which is what the router does, and inaccessible ways drop out
(8 779 → 8 627 nodes for the Funchal cell with `trekking`). `--limit n` keeps
sample files small; a whole cell is ~8 800 nodes and ~6.6 MB of JSON.

**`eval-profile <profile.brf> <tagsfile>`** builds a `BExpressionMetaData` from
`brouter/profiles/lookups.dat`, parses the profile into a
`BExpressionContextWay`, and for each line of `key=value` pairs encodes the tags
(`createNewLookupData` → `addLookupValue` → `encode`) and evaluates them in both
directions. It prints the encoded bitmap as hex, the tag string BRouter decodes
back out of it, the keys it did not recognise, and every variable that has a
value — 65 of them for `trekking`. Floats are printed with `Float.toString`, so
the Dart side can compare exact `float` bit patterns rather than doubles.

Three R3 options change the output format (the default format above is
unchanged): `--bits` prints every variable as the hex of
`Float.floatToIntBits` and lists every existing variable (NaN included);
`--compact` additionally de-duplicates the per-case variable vectors
(`"vectors"` plus a `[forward, reverse]` index pair per case, no tags -- the
case order is the order of the tags file), which keeps a 35 000-line corpus
at 0.5–2 MB per profile; `--encode` adds the encoded hex / decoded string of
every case. `--context node --way-tags "<tags>"` evaluates the node context
(hash size 0, like `ProfileCache`) after evaluating its foreign way context
with the given way; the "reverse" direction then means
`nodeaccessgranted=yes`. Both new formats also print `usedTagList()`.

**`way-tags <tile> [--kind way|node]`** decodes every micro-cache of the tile
(no validator) and prints every distinct way tag string
(`getKeyValueDescription`, forward direction) or node tag string, one per
line, sorted. `dump/samples/tags-large.txt` is the union of both tiles
(35 099 way tag sets), `node-tags-large.txt` the node tag sets (769).
`tags-units.txt` lists unit-carrying values (`12'6"`, `5000lbs`, `10mph`...)
for `BExpressionContext.addLookupValue`'s conversion; it needs a lookup table
with `*` values, i.e. the upstream test table in
`app/packages/brouter_dart/test/fixtures/` (the shipped `lookups.dat` has
none), see the header of the file.

**`math-vectors <outdir>`** writes `float.json`: `Float.parseFloat`
(including decimal strings on float midpoints), `Float.toString`, float
`+ - * /`, int/float conversions, `String.format("%3.1f")`,
`Integer.parseInt`, `Arrays.hashCode(float[])`, `Character.isWhitespace` and
`String.split` results as bit patterns, for the Dart emulation in
`app/packages/brouter_dart/lib/src/jfloat.dart`. Notable: JDK 17's
`Float.toString` (the pre-JDK-19 `FloatingDecimal.dtoa`) prints a different
last digit than exact arithmetic for 4 of the 17 353 sampled floats, because
its `long` branch overflows; the Dart port reproduces that.

**`nodes-cache-walk ... --profile <brf>`** parses the real profile instead
of the one-line "every way" profile (and does not call `setAllTagsUsed`,
like `RoutingEngine`), so the walk sees the filtered graph; the JSON then
carries a `"profile"` entry.

### What the upstream API does and does not allow

Everything the tool needs is public in 1.7.10. Three limits are worth recording
for whoever writes the Dart equivalent:

* `PhysicalFile.ra` (the `RandomAccessFile`) is **package-private** and
  `PhysicalFile` has no `close()`, so the tool cannot close the file handle and
  relies on JVM exit. Harmless for a one-shot dump.
* `BExpressionContext` has **no public way to enumerate its variable table**:
  `variableData` is private and `getVariableValue(int)` is package-private, only
  `variableName(int)` is public and there is no count. `eval-profile` therefore
  reports the 20 build-in way variables (`BExpressionContextWay`'s
  `buildInVariables`) plus every name the `.brf` assigns, found by scanning the
  profile for `assign <name>`, and reads them back with the public
  `getVariableValue(String, float)`. A variable that a profile only ever uses as
  a local intermediate inside an expression, without an `assign`, would be
  missed — none of the six shipped profiles has one.
* `MicroCache` exposes decoded node **bytes**, not objects; the node/link
  structure only exists after `OsmNode.parseNodeBody`, which needs an
  `OsmNodesMap` and an `IByteArrayUnifier`. The dump therefore reports both: the
  raw description/geometry bytes (for byte-level parity) and the decoded view.

`dump/samples/` holds `tags.txt` (21 representative way tag sets, from
`highway=cycleway surface=asphalt` to `highway=motorway` and `route=ferry`),
`eval-trekking.json` and `eval-gravel.json`, three micro-cache dumps: Funchal
raw, Funchal filtered through `trekking`, and Reykjavík raw, and the R3
corpora `tags-large.txt`, `node-tags-large.txt` and `tags-units.txt`. The
R3 evaluation vectors themselves live with the tests
(`app/packages/brouter_dart/test/vectors/expressions/`).

## Caveats

* **The corpus is only valid for the checksums in `tiles.sha256`.** See above.
* The two tiles are islands with a modest, mostly paved network. They exercise
  the profiles and the search well, but they contain no motorway network, no
  ferry routes between the sampled points, and comparatively little of what an
  Alpine tile would throw at `mtb` or `gravel`. Widening coverage means more
  tiles and a much larger `corpus/responses/`.
* `messages` are counted, not compared field by field, in `check_corpus.py` —
  but the body `sha256` covers them exactly, so any change in a message shows up
  as a hash mismatch.
* There is no "mini rd5 built from a Geofabrik extract in Git LFS" here. That
  would need `brouter-map-creator` and a full OSM import; the two small real
  tiles give the same coverage at 4 MB, and the checksum binding keeps them
  honest. If the port later needs a synthetic tile, it belongs next to this
  directory, not inside it.
* `serve.sh` refuses to start when something already answers on port 17777, so a
  stale server can never silently record a corpus against the wrong segments.
  Set `BROUTER_ORACLE_PORT` to use a different port.
