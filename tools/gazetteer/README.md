# Offline gazetteer

Search for places, streets and rider POIs with no network, the way Organic Maps
and OsmAnd do it: one small SQLite file per routing tile, downloaded next to the
`.rd5` it belongs to.

Tiles are named exactly like BRouter segments — `W20_N30`, `E5_N45` — so
`W20_N30.gaz` sits beside `W20_N30.rd5` on the mirror and the app asks for it
with the tile name it already has
(`app/packages/velorki_brouter/lib/src/tiles.dart`). On the phone the file lives
at `<appSupport>/brouter/gazetteer/<TILE>.gaz`, read-only.

| File | |
|---|---|
| `build.py` | reads an OSM PBF extract, writes one `<TILE>.gaz` per tile it touches |
| `merge.py` | merges the partial tiles of several extracts into one file per tile |
| `query.py` | runs the app's two queries from the command line |
| `check.py` | validates one `.gaz` and prints a one-line summary |
| `manifest.py` | adds the `gazetteer` object to a mirror's `manifest.json` |
| `test_gazetteer.py` | the tests, run against a Liechtenstein build |
| `fixtures/` | two committed `.gaz` files and their hashes |

## What a file holds

| Table | Rows | What it is |
|---|---|---|
| `places` | one per settlement | `place=city\|town\|village\|hamlet\|suburb\|neighbourhood\|locality\|island` nodes and areas, with population where OSM has it |
| `pois` | one per feature | what a rider needs on the road and what a rider searches for as a destination, always named: the 25 kinds below |
| `streets` | one per street name per place | every named `highway=*` way, the many ways of one street merged into one row. Only with `--streets` |
| `search` | one per row above | the FTS5 index the search box queries |
| `meta` | six | schema version, tile, build time, source, what is in the file |

Default content is places plus POIs, which keeps every tile to a few MB.
Streets are opt-in and roughly quadruple the file; the app handles them when
`meta.has_streets` is `1`.

## POI kinds

The kind is the first match down this list, so a café in a historic building is
a `cafe`, a museum in a building is a `museum`, and `building` is only ever the
fallback. One object gets one row.

| kind | tags |
|---|---|
| `drinking_water`, `cafe`, `bicycle_repair_station`, `shelter` | `amenity=` the same value |
| `bicycle_shop` | `shop=bicycle` |
| `station` | `railway=station` |
| `viewpoint` | `tourism=viewpoint` |
| `peak` | `natural=peak` |
| `park` | `leisure=park` |
| `attraction` | `tourism=attraction\|theme_park\|zoo\|aquarium` |
| `museum` | `tourism=museum\|gallery` |
| `historic` | any `historic=*`; `historic=yes` only when nothing else fits |
| `place_of_worship` | `amenity=place_of_worship` |
| `hospital` | `amenity=hospital\|clinic` |
| `university` | `amenity=university\|college` |
| `stadium` | `leisure=stadium\|sports_centre\|ice_rink\|swimming_pool` |
| `mall` | `shop=mall\|department_store` |
| `airport` | `aeroway=aerodrome` |
| `ferry_terminal` | `amenity=ferry_terminal` |
| `tower` | `man_made=tower\|communications_tower\|observation_tower\|mast` |
| `lighthouse` | `man_made=lighthouse` |
| `water` | `natural=water` (any `water=*`), `landuse=reservoir`, `natural=bay\|strait\|lagoon` |
| `beach` | `natural=beach` |
| `nature_reserve` | `leisure=nature_reserve`, `boundary=national_park\|protected_area` |
| `building` | any other `building=*`, except `building=no` |

An unnamed object is never stored. Names are trimmed, and a name with no letter
in it is dropped: that is a house number somebody typed into the name field, or
a numbered boundary stone, and nobody searches for `12`.

Nodes, ways **and areas** are read, so a lake, a park, a nature reserve or a
big building mapped as a multipolygon relation lands in the file like any other
object. An area keeps the identity of what it was assembled from: `osm_type`
`'r'` with the relation id, or `'w'` with the way id for a closed way. A closed
way arrives twice, as the way and as the area, and is counted once.

## Schema

```sql
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
-- schema_version='1', tile, built_at (ISO-8601 UTC), source, has_streets, has_pois

CREATE TABLE places (
    id         INTEGER PRIMARY KEY,
    name       TEXT NOT NULL,
    kind       TEXT NOT NULL,    -- city, town, village, hamlet, suburb,
                                 --   neighbourhood, locality, island
    lat        INTEGER NOT NULL, -- degrees * 1e7, rounded
    lon        INTEGER NOT NULL,
    population INTEGER,          -- NULL when OSM has none
    admin_id   INTEGER,          -- places.id of the town/city this sits in
    osm_type   TEXT,             -- 'n', 'w', 'r'; NULL when unknown
    osm_id     INTEGER
);

CREATE TABLE streets (
    id       INTEGER PRIMARY KEY,
    name     TEXT NOT NULL,
    lat      INTEGER NOT NULL,
    lon      INTEGER NOT NULL,
    place_id INTEGER,           -- places.id: addr:city, else nearest within 5 km
    osm_type TEXT,              -- always NULL: a street is merged out of many ways
    osm_id   INTEGER
);

CREATE TABLE pois (
    id       INTEGER PRIMARY KEY,
    name     TEXT NOT NULL,     -- unnamed POIs are not stored
    kind     TEXT NOT NULL,     -- one of the 25 kinds, see "POI kinds" above
    lat      INTEGER NOT NULL,
    lon      INTEGER NOT NULL,
    place_id INTEGER,
    osm_type TEXT,
    osm_id   INTEGER
);

CREATE VIRTUAL TABLE search USING fts5(
    name, content='', columnsize=0,
    tokenize='unicode61 remove_diacritics 2'
);

CREATE INDEX idx_places_pos  ON places(lat, lon);
CREATE INDEX idx_streets_pos ON streets(lat, lon);
CREATE INDEX idx_pois_pos    ON pois(lat, lon);
```

Page size 4096, journal mode DELETE (the phone opens it read-only), `VACUUM`ed.

Five decisions are load-bearing:

**One id space.** `id` comes from a single counter across `places`, `streets`
and `pois`, so an FTS `rowid` names exactly one row in exactly one table. A
`UNION ALL` view over the three reads better but SQLite materialises it on every
query: the same search went from 0.4 ms to 250 ms.

**The FTS index is contentless and has no prefix index.** `content=''` drops a
second copy of every name (a fifth of the file); `columnsize=0` drops bm25's
length normalisation, worth nothing when every document is one short name;
`prefix='2 3 4'` was 14 MB on a dense tile and measured *slower* at every query
length, because the cost of a short query is reading the doclist, not finding
the terms. The way to keep the first keystrokes quick is to not search until the
third.

**Integer coordinates.** SQLite stores a `REAL` in 8 bytes; 1e-7 degrees fits in
4–5, which is a quarter of a dense street table and its index.

**`osm_type` / `osm_id` are the merge key.** Both are nullable and the app
ignores them; every tool accepts a file with or without the two columns (the
`W20_N30` fixture predates them). A place or POI carries the node or way it
came from, so `merge.py` can tell the same object out of two overlapping
extracts from two different objects. A street row is the mean of many ways and
has no single identity, so it keeps `NULL`s and is matched by name, place and
position instead.

**Foreign keys, not repeated names.** A place name is ~12 bytes repeated on
every street of that place. `admin_id` and `place_id` can only point inside the
same file, so a village whose nearest town falls in the neighbouring tile keeps
a `NULL`.

Reverse lookup needs no extra table: the three positional indexes turn "what is
near me" into a bounding box plus a sort.

## Query contract

What the app runs, and what `query.py` runs:

1. Tokenise on whitespace, drop empties, quote each token (`"` doubled inside),
   append `*` to the **last** token only: `west 125` → `"west" "125"*`.
2. `SELECT rowid, bm25(search) AS rank FROM search WHERE search MATCH ? ORDER BY rank LIMIT 60`.
3. Hydrate each rowid by primary key from `places`, `streets`, `pois` — one
   prepared statement each, first hit wins.
4. Rank: bm25 ascending, ties by the shorter name (the index keeps no column
   sizes, so bm25 cannot tell `Monte` from `Monte Tea House`), then population
   descending, then distance to the map centre when there is one. Return at
   most 10.

Do not query below 3 characters; two-letter prefixes match tens of thousands of
rows and cost 10–70 ms on a dense tile.

```sh
./query.py fixtures/E5_N45.gaz muhleholz
./query.py fixtures/E5_N45.gaz vad --near 47.141,9.521
./query.py --reverse fixtures/E5_N45.gaz 47.1410 9.5215
```

## Building

```sh
pip install osmium                                  # pyosmium 4.x, ships wheels
./build.py liechtenstein.osm.pbf --out gaz          # places + pois
./build.py liechtenstein.osm.pbf --out gaz --streets
./build.py portugal-latest.osm.pbf --out gaz --tiles W20_N30   # keep one tile
./check.py gaz/*.gaz
```

The PBF is streamed. Node coordinates go through an osmium location cache so
only tagged objects reach Python; `--node-cache auto` (the default) keeps it in
memory under 150 MB of PBF and in a temporary file above that. Override with
`--node-cache flex_mem` or `--node-cache sparse_file_array,/path`.

An object lands in a tile by its representative point: the node itself, the
mean of a way's nodes, or the mean of the outer rings of an assembled area. A
street that crosses a tile boundary appears once, in the tile its centre falls
in.

Areas cost a second pass over the file: osmium indexes the multipolygon and
boundary relations first, then assembles each one while the ways stream past.
On Liechtenstein that is +0.2 s of 0.5 s and +3 MB of peak RSS, on Malta
0.9 s → 2.1 s and 82 MB → 87 MB. It buys the lakes, the reserves and the big
buildings, which exist as relations and nothing else.

## Merging

No Geofabrik extract covers a whole 5 degree tile and neighbouring extracts
overlap, so a mirror is built one extract at a time and the partial tiles are
merged:

```sh
./build.py liechtenstein.osm.pbf --out gaz/liechtenstein --streets
./build.py switzerland.osm.pbf   --out gaz/switzerland   --streets
./build.py austria.osm.pbf       --out gaz/austria       --streets
./merge.py mirror gaz            # every *.gaz under gaz, grouped by tile name
./manifest.py mirror             # then the manifest, over the merged files
```

`merge.py <out_dir> <in_dir>...` searches the input directories recursively, so
one directory per extract or the flat download of a CI matrix both work. Per
tile it

* validates every input with `check.py` and stops before writing anything if
  one fails,
* drops rows that repeat an `(osm_type, osm_id)` already seen, and streets that
  repeat a name + place name + position rounded to 1e-3 degrees (~100 m),
* hands out ids from a single counter across the three tables, as `build.py`
  does, and remaps `admin_id` / `place_id` onto the surviving rows (a dropped
  duplicate's references go to its survivor),
* rebuilds the FTS index, writes `meta` (`source` is the comma-joined distinct
  sources of the inputs, `has_streets` / `has_pois` are set when any input has
  them) and `VACUUM`s.

A tile only one input holds goes through the same path, so the output is always
canonical. `merge.py` uses the standard library only — the merge job needs no
pyosmium.

## Fixtures

`fixtures/fixtures.sha256` pins both files.

| File | Built from | Content | Size |
|---|---|---|---:|
| `E5_N45.gaz` | `liechtenstein.osm.pbf`, `--streets` | 98 places, 1,313 streets, 542 pois | 204,800 B |
| `W20_N30.gaz` | `portugal-latest.osm.pbf`, `--tiles W20_N30` | 1,769 places, 1,022 pois | 262,144 B |

```sh
./build.py liechtenstein.osm.pbf --out fixtures --streets
./build.py portugal-latest.osm.pbf --out fixtures --tiles W20_N30
(cd fixtures && sha256sum E5_N45.gaz W20_N30.gaz > fixtures.sha256)
```

Liechtenstein covers all three kinds and plenty of umlauts to prove the
tokenizer folds them: `muhleholz` finds the village `Mühleholz` and the street
`Im Mühleholz`, `vad` puts the town `Vaduz` first, `grauspitz` finds two peaks.
It also covers the landmarks: `Rathaus Vaduz` is a `building`, `Kathedrale St.
Florin` a `place_of_worship`, `Schloss Vaduz` a `historic` built from a
multipolygon relation. Landmarks took the file from 155,648 B to 204,800 B,
1.3× — the street table is most of this one. Without `--streets` the same
build went 65,536 B → 114,688 B (1.8×), and Malta, which is built up, 2.5×.
Madeira is `W20_N30`, the tile the integration tests already mirror, and holds
`Funchal`; Portugal is the only Geofabrik extract that covers it, so the
mainland tiles are discarded with `--tiles`. `W20_N30.gaz` was built before the
`osm_type` / `osm_id` columns existed and is kept that way on purpose: it is
what proves the tools still read a file without them.

Run the tests from the repo root:

```sh
GAZ_EXTRACT=/path/to/liechtenstein.osm.pbf \
  python -m unittest tools/gazetteer/test_gazetteer.py
```

## Mirror integration

A mirror serves `<TILE>.gaz` next to `<TILE>.rd5`. `manifest.json` tile entries
gain an optional object; a missing one means no gazetteer for that tile and the
app falls back to online search.

```json
{ "tile": "W20_N30", "bytes": 1527283, "updatedAt": "...", "sha256": "...",
  "gazetteer": { "bytes": 262144, "sha256": "<hex>", "updatedAt": "..." } }
```

`brouter/updater/sync.sh` writes it for any `.gaz` it finds beside an rd5 (always
hashed — the files are small). For a mirror built some other way,
`manifest.py <dir>` adds, refreshes and removes the objects in place; it is
idempotent, validates every file with `check.py` first, and exits non-zero on a
`.gaz` whose `schema_version` is not `1` or whose `meta.tile` does not match its
file name. `app/tool/itest_mirror.sh` uses both.

## Measured

Geofabrik extracts of 2026-09-15/16, 8-core laptop, 16 GB RAM, sizes after
`VACUUM`.

| Extract | PBF | Tile | places | pois | streets | Default | `--streets` |
|---|---:|---|---:|---:|---:|---:|---:|
| liechtenstein | 3.5 MB | `E5_N45` | 98 | 542 | 1,313 | 0.11 MB | 0.20 MB |
| iceland | 65 MB | `W25_N60` | 366 | 851 | — | 0.14 MB | — |
| berlin | 99 MB | `E10_N50` | 598 | 4,052 | 20,830 | 0.40 MB | 1.75 MB |
| portugal | 423 MB | `W20_N30` | 1,769 | 1,022 | — | 0.26 MB | — |
| new-york | 496 MB | `W75_N40` | 3,789 | 12,437 | 160,958 | 1.23 MB | 11.41 MB |

| Extract | Wall, default | Wall, `--streets` | Peak RSS |
|---|---:|---:|---:|
| liechtenstein | 0.5 s | 0.7 s | 59 MB |
| iceland | 4 s | — | 299 MB |
| berlin | 11 s | 22 s | 247 MB |
| portugal | 36 s | — | 969 MB |
| new-york | 55 s | 77 s | 1.07 GB |

Only the liechtenstein row was re-measured after landmarks and areas landed;
the four bigger extracts are from before and their `pois` and sizes are now
low by roughly 3–6× on POIs and 2–3× on the default file. Roughly 3–5 MB of
PBF per second on one core now that every file is read twice. Streets are
still the whole size question: without them the densest tile measured here is 1.2 MB against a
119 MB `.rd5`, with them 11.4 MB. The New York extract covers less than half of
`W75_N40`; a complete build of that tile from `us-northeast` was ~78 MB under
the old schema and lands near 40 MB under this one, all of it streets.

## What is missing versus Photon

Photon is a full geocoder; this is a search box that works on a plane.

* **House numbers.** Not collected. "Hauptstraße 12" finds the street and drops
  the number.
* **Fuzzy matching.** FTS5 does prefix matching and nothing else; "Munchen" for
  "München" finds nothing.
* **Admin hierarchy.** `admin_id` and `place_id` are geometry, not boundaries,
  and stop at the tile edge. No country, state or district, so Springfield,
  Massachusetts cannot be told from Springfield, Illinois.
* **Anything outside places, streets and the 25 POI kinds** — squares, rivers,
  general shops, individual addresses.
* **Alternative names.** `name:de`, `old_name`, `alt_name`, `short_name` are not
  indexed.

## Planet builds

The planet is built on GitHub Actions by the `publish-gazetteer` workflow in
[orkitec/velorki-data](https://github.com/orkitec/velorki-data), one Geofabrik
leaf extract per step (about 510 extracts, ~79 GB of PBF), spread over a
matrix of runners that each hold one PBF at a time, then `merge.py` over the
partial tiles and `manifest.py` per release shard. It runs after every tile
snapshot and can be dispatched for one continent or a list of extracts. A
runner has ~14 GB of disk and 16 GB of RAM, which is why the unit is the leaf
extract and not the continent; the default build (places and POIs) needed about
1 GB of RAM per 500 MB of PBF before areas, and area assembly adds the
relation index and the assembler buffers on top — not measured on an extract
that size yet. `--streets` planet-wide would also need the street list spilled
to disk during the build, which is not written.
