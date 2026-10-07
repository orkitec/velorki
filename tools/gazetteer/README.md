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
| `street_numbers.py` | the `street_numbers` blob: thinning, encoding, decoding, the lookup |
| `translit.py`, `translit.json` | the text the index holds for a name: lower case, Cyrillic and Greek in Latin letters, Cyrillic spelled two ways; the table is shared with the app |
| `manifest.py` | adds the `gazetteer` object to a mirror's `manifest.json` |
| `testset.py` | samples a `.gaz` into mistyped query/expected pairs for the search-quality scorer |
| `test_gazetteer.py` | the tests, run against a Liechtenstein build |
| `fixtures/` | two committed `.gaz` files and their hashes |
| `testset/` | the search-quality test set: generated, hand-written and adopted cases |

## What a file holds

| Table | Rows | What it is |
|---|---|---|
| `places` | one per settlement | `place=city\|town\|village\|hamlet\|suburb\|neighbourhood\|locality\|island` nodes and areas, with population where OSM has it |
| `pois` | one per feature and kind | what a rider needs on the road and what a rider searches for as a destination: the 38 kinds below, named — or unnamed for the eight utility kinds |
| `streets` | one per street name per place | every named `highway=*` way, the many ways of one street merged into one row |
| `aliases` | one per extra name | `name:en`, `int_name`, `alt_name`, `old_name`, `official_name`, `short_name` of a row above; for a place with `importance` and a POI with `importance` ≥ 10 also every `name:<lang>`, at most 80 |
| `street_numbers` | one per street with addresses | its house numbers, odd and even side, thinned to the points that keep interpolation within 20 m, in one blob |
| `search` | one per place, street, **named** poi and alias | the FTS5 index the search box queries, over the transliterated names |
| `vocab` | one per word of `search` | the word and how many rows hold it, copied from the index |
| `meta` | seven | schema version, tile, build time, source, what is in the file, the index's script |

Streets are built by default and are most of the file; `--no-streets` leaves
them and the house numbers out and takes a tile back to a few hundred KB. The
app reads `meta.has_streets` to know which it got.

## POI kinds

The kind is the first match down this list, so a café in a historic building is
a `cafe`, a hotel in one is a `hotel`, a museum in a building is a `museum`, and
`building` is only ever the fallback. One object gets one row — except that
`drinking_water=yes` on something that is not water (a toilet, a campsite, a
hut) earns a **second** row of kind `drinking_water` for the same object, so a
rider looking for the nearest tap finds it. That is why the identity of a row,
the key `build.py`, `merge.py` and `check.py` all deduplicate on, is
`(osm_type, osm_id, kind)` and not `(osm_type, osm_id)`.

The first group is what a tour needs on the road; the rest are landmarks
somebody types as a destination.

| kind | tags |
|---|---|
| `drinking_water` | `amenity=drinking_water\|water_point`, `man_made=water_tap`, or any object with `drinking_water=yes`; never with `drinking_water=no` |
| `cafe`, `restaurant`, `fast_food`, `ice_cream`, `bicycle_repair_station`, `shelter`, `toilets`, `bicycle_rental`, `bicycle_parking`, `pharmacy` | `amenity=` the same value; restaurants, fast food and ice cream only with a name (`ice_cream` also `shop=ice_cream`) |
| `fuel` | `amenity=fuel`, named after its `brand` when it has no name, kept unnamed otherwise: on a long ride it is water, food, toilets and air |
| `compressed_air` | `amenity=compressed_air`, named or not: air for tyres |
| `charging_station` | `amenity=charging_station` with `bicycle=yes`, `bicycle:charging=yes` or a `socket:*` key naming a bicycle |
| `picnic_site` | `tourism=picnic_site` |
| `bicycle_shop` | `shop=bicycle` |
| `station` | `railway=station` |
| `viewpoint` | `tourism=viewpoint` |
| `peak` | `natural=peak` |
| `park` | `leisure=park` |
| `mountain_pass` | `mountain_pass=yes`, `natural=saddle` |
| `camp_site` | `tourism=camp_site\|caravan_site` |
| `hotel` | `tourism=hotel\|motel` |
| `hostel` | `tourism=hostel\|guest_house\|chalet` |
| `alpine_hut` | `tourism=alpine_hut\|wilderness_hut` |
| `supermarket` | `shop=supermarket\|convenience` |
| `bakery` | `shop=bakery` |
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

**Unnamed rows.** `pois.name` is nullable, but only for the eight utility kinds
`drinking_water`, `toilets`, `bicycle_repair_station`, `shelter`,
`bicycle_rental`, `charging_station`, `picnic_site`, `bicycle_parking`: a tap or
a toilet is worth a row without a name because the app looks for the *nearest*
one rather than typing for it. Such a row is **not** in the FTS index — there is
nothing to match — and `idx_pois_pos` is how it is found. Every other kind is
still stored only when it has a name.

Names are trimmed, and a name with no letter in it is not a name: that is a
house number somebody typed into the name field, or a numbered boundary stone,
and nobody searches for `12`. The row keeps its position and loses the name,
which leaves it a row only when its kind may go unnamed.

Nodes, ways **and areas** are read, so a lake, a park, a nature reserve or a
big building mapped as a multipolygon relation lands in the file like any other
object. An area keeps the identity of what it was assembled from: `osm_type`
`'r'` with the relation id, or `'w'` with the way id for a closed way. A closed
way arrives twice, as the way and as the area, and is counted once.

## Schema

```sql
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
-- schema_version='1', tile, built_at (ISO-8601 UTC), source, has_streets, has_pois,
-- search_script='latin' (the index holds translit(name); absent in older files)

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
    osm_id     INTEGER,
    importance INTEGER           -- see "importance" below; NULL at 0
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
    id         INTEGER PRIMARY KEY,
    name       TEXT,            -- NULL only on the eight utility kinds
    kind       TEXT NOT NULL,   -- one of the 43 kinds, see "POI kinds" above
    lat        INTEGER NOT NULL,
    lon        INTEGER NOT NULL,
    place_id   INTEGER,
    osm_type   TEXT,
    osm_id     INTEGER,
    importance INTEGER          -- as on places
);

CREATE TABLE aliases (
    id     INTEGER PRIMARY KEY,   -- from the same counter as the three above
    ref_id INTEGER NOT NULL,      -- the places/streets/pois row this name belongs to
    name   TEXT NOT NULL          -- see "aliases" below
);

CREATE TABLE street_numbers (
    street_id INTEGER PRIMARY KEY,  -- streets.id; no row: no addresses
    data      BLOB NOT NULL         -- see "street_numbers.data" below
);

CREATE VIRTUAL TABLE search USING fts5(
    name, content='', columnsize=0,
    tokenize='unicode61 remove_diacritics 2'
);

CREATE TABLE vocab (
    term TEXT PRIMARY KEY,          -- a term of the search index
    docs INTEGER NOT NULL           -- how many rows hold it
) WITHOUT ROWID;

CREATE INDEX idx_places_pos  ON places(lat, lon);
CREATE INDEX idx_pois_pos    ON pois(lat, lon);
CREATE INDEX idx_aliases_ref ON aliases(ref_id);
```

Page size 4096, journal mode DELETE (the phone opens it read-only), `VACUUM`ed.

**`importance`** is fame without reading any language: the number of the
object's tags matching `^name:[a-z]{2,3}(-[A-Za-z]{2,8})?$` (`name:en`,
`name:zh-Hans`; not `name:etymology`, `name:left`, `name_1`), plus 5 when it
has a `wikidata`, `wikipedia` or `wikipedia:<lang>` tag, at most 255 and NULL
at 0. Where one row comes from several objects (a closed way and its area, a
duplicate across merged extracts) the highest wins. Streets have none; a file
without the column reads as all NULL.

**`aliases`** are, in this order and each name once: the values of
`name:en`, `int_name`, `alt_name`, `old_name`, `official_name` and
`short_name` (semicolon-separated values one name each, never the primary
name); then, for a place whose `importance` is not NULL and a POI whose
`importance` is at least 10, every `name:<lang>` value (the same key rule as
`importance`) in tag order, dropping the primary name and any name already
there compared lower-cased, at most 80 of them. Streets get only the six tags:
on a national extract the language names are the primary name again.

**The index holds `index_text(name)`**, not the name. `translit(name)` is the
name lower-cased (Python `str.lower()`), then `translit.json` applied —
`starts` at the start of a word (Greek `μπ` → `b`), `digraphs` anywhere (`ου`
→ `ou`, `αυ`/`ευ` → `av`/`ev`), then every `letters` character by its Latin
value (`Александър` → `aleksandar`, `Ναύπλιο` → `navplio`, `Ђурђевдан` →
`djurdjevdan`), everything else left as it is — Latin diacritics are the
tokenizer's job. A name with і, ї, є or ґ is indexed in both spellings; the
Ukrainian system is the one riders meet on signs and in the official
romanisation. The second, `translit_alt(name)`, is the name lower-cased,
`starts_uk` at the start of a word, then `letters_uk` (`х` → `kh`, `и` → `y`,
`г` → `h`, `ї` → `i`, `я` → `ia`; no digraphs), so `Київ` is `kiyiv kyiv` and
`Кривий Ріг` `kriviy rig kryvyi rih`. Only the second spelling's words the
first does not already hold are added, after a space. A Bulgarian, Russian or
Serbian name, and a Ukrainian one without those letters (`Хмельницький`), is
`translit(name)` alone. The tables keep the names as written; `vocab` holds
the Latin words. A file built this way has `meta.search_script = 'latin'`;
for a tile without Cyrillic or Greek the index is the same as without it. `check.py` matches a name through
the index transliterated and rejects a `latin` file with a term holding a
letter of either table.

`vocab` is written last, after the FTS `optimize`, from
`fts5vocab(main, 'search', 'row')`: exactly the index's terms with their
document counts. `fts5vocab` works the counts out by walking each term's whole
list of rows, which is slow for a common word; the app range-scans `vocab`
(`term >= ? AND term < ?`) and looks single terms up in it instead.

Older files may have a `house_numbers` table instead of `street_numbers`
(`street_id`, `number`, `lat`, `lon` in 1e-7 degrees, primary key
`(street_id, number)`: anchors at the lowest, the highest and every twentieth
number) and no `vocab`. Every tool and the app read both; a file has one or
neither, never both.

### `street_numbers.data`

An address belongs to the street row of the same name nearest within 2 km;
per street the unique numbers (the first address of a repeated number wins)
are split by parity and each side is thinned on its own: the first and the
last point stay, and between two kept points the skipped point furthest from
where interpolation by number between them puts it is kept when that is more
than 20 m (`HOUSE_TOLERANCE_M`), then both halves are looked at again
(Douglas-Peucker over the number axis). The blob, version 1:

```
byte 0     1, the blob format version
odd run    varint(count), then count points
even run   varint(count), then count points
point      varint(number - previous number)    previous is 0 at the start of each run;
                                               numbers strictly ascend within a run
           zigzag_varint(lat_q - cursor lat)   the cursor starts at (0, 0) at the start
           zigzag_varint(lon_q - cursor lon)   of the blob, is not reset between runs,
                                               and is always the previous point written
```

`lat_q` / `lon_q` are degrees in units of 1e-5 (`round(lat_e7 / 100)`).
`varint` is unsigned LEB128: seven bits a byte, least significant group first,
the high bit set when more bytes follow. `zigzag(n) = (n << 1) ^ (n >> 63)` on
64-bit `n` (0, -1, 1, -2, 2 → 0, 1, 2, 3, 4). Either run may be empty.

Five decisions are load-bearing:

**One id space.** `id` comes from a single counter across `places`, `streets`,
`pois` and `aliases`, so an FTS `rowid` names exactly one row in exactly one
table; a rowid that is in none of the first three is an alias. A
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

**`osm_type` / `osm_id` are the merge key**, plus `kind` for a POI. All are
nullable and the app ignores them; every tool accepts a file with or without the
two columns (the `W20_N30` fixture predates them). A place or POI carries the
node or way it came from, so `merge.py` can tell the same object out of two
overlapping extracts from two different objects; a POI's key carries the kind
as well, because one object can be a `toilets` row and a `drinking_water` row. A street row is the mean of many ways and
has no single identity, so it keeps `NULL`s and is matched by name, place and
position instead.

**Foreign keys, not repeated names.** A place name is ~12 bytes repeated on
every street of that place. `admin_id` and `place_id` can only point inside the
same file, so a village whose nearest town falls in the neighbouring tile keeps
a `NULL`.

**Streets carry no positional index.** The app finds a street by name through
the FTS index and its house numbers by `street_id`; nothing on the phone asks
which street is near a point, and `idx_streets_pos` was a tenth of a tile. Every
tool still reads a file that has it — files built before this trim keep it — and
`query.py --reverse` falls back to one full scan of `streets`, marked `(scan)`.

Reverse lookup needs no extra table: the positional indexes on `places` and
`pois` turn "what is near me" into a bounding box plus a sort.

## Query contract

What the app runs (`GazetteerStore.lookup`); `query.py` runs only the plain
first look, for poking at a file.

1. **Read the query** (`search_text.dart`): every word is asked for as typed
   and transliterated with the same table (`Софи` → `sofi`), so it matches
   a `latin` file and an older one alike; the words the tokenizer would cut
   (`C/ Mayor` → `c mayor`), a house number taken out wherever it stands
   (`12`, `12a`, `12а`, `12 bis`, `12/3`, `12/A`, `40-42`, `12a-14`, `92-10`;
   an ordinal such as `42nd` or `2º` is a name), a postcode dropped (five
   digits, or four digits and two letters).
2. **First look**: every word a quoted prefix (`"w"* AND "42nd"*`), both
   spellings of `ß`/`ss`; a word in more than 15 000 rows (`de`, `rue`,
   `street`) or of two letters is matched exactly, a lone letter left to the
   scoring — prefixes that short merge thousands of term lists.
3. **Read the rows**: up to 1 000 matches are all read in one batched query
   per table (`id IN (SELECT value FROM json_each(?))`), up to 20 000 the 300
   per table nearest to the map centre (ordered in SQL), beyond that the
   first 1 000. A rowid in `aliases` stands for its `ref_id` row, shown under
   the primary name.
4. **Score in Dart**: per word equal, prefix, abbreviation (its letters in
   order, either way: `rd`/`road`, `st`/`saint`), one or two edits
   (Damerau-Levenshtein), two words written as one or one as two; weighted by
   length, times how much of the name was asked for, plus a bonus for the very
   same name, and more for a well-known row (`importance` above 5, so a
   Wikidata link alone does not count). A word the row's place or that
   place's parent answers counts
   too (`hauptstrasse berlin`). Then less for the way to the map centre (0.06
   per doubling of the kilometres), more for a bigger place, more for a street
   when there is a house number, and the rider's group order when they set
   one.
5. **Named place**: when the last one to three words are exactly a
   settlement's name (or alias) and no row holds every typed word, or a comma
   sets them apart — or the first ones are, before a comma (`Budapest, Fő
   utca`) — the other words are searched around that settlement and rows in
   it are measured from there.
6. **Second look**, only when no row within 30 km answers well: each word
   unknown to the index gets its alternatives from the index's own words —
   typos (same first letter, ≤ 1 edit up to five letters, ≤ 2 above), short
   words a long one may be stored as and long words a short one may stand
   for, splits into a stored word and the start of another; neighbouring words
   are tried joined. If that still answers nothing decently, words are left
   out: each in turn up to four words, then from the end, then from the start,
   stopping at the first that answers. The words a guessed row was read as
   come back as the corrected query.

The words come from `vocab` (term, row count) when the file has it, and from
an `fts5vocab` table in the connection's `temp` schema otherwise, which gives
the same answers but walks every word's list of rows to count it.

Do not query below 3 characters.

### House numbers

The number is resolved against the `street_numbers` points of each street
hit, on the side of its parity:

| | position | |
|---|---|---|
| between the first and the last point of its side | interpolated by number between the two points that bracket it (a point itself when it is one) | exact: within 20 m |
| past either end of its side | the nearer end point of its side | approximate |
| its side has no points | the nearer end point of the other side | approximate |
| the street has no row | the street's own point | approximate |

An older file's `house_numbers` anchors keep their own rule: an anchor is
exact; between two anchors (either parity) interpolated, past either end the
nearer end anchor, no anchors the street's point, all approximate.

An approximate position is marked `≈` (`SearchResult.approximate` in the app).

```sh
./query.py fixtures/E5_N45.gaz muhleholz
./query.py fixtures/E5_N45.gaz vad --near 47.141,9.521
./query.py fixtures/E5_N45.gaz "114 landstrasse"      # within its side: exact
./query.py fixtures/E5_N45.gaz "landstrasse 5000"     # ≈ past the end
./query.py fixtures/E5_N45.gaz --near 47.141,9.521 --kind drinking_water
./query.py --reverse fixtures/E5_N45.gaz 47.1410 9.5215
```

`--near LAT,LON --kind <kind>` is the other query the app runs: the rows of one
POI kind nearest to a point, named or not, with their distance — a bounding box
on `idx_pois_pos` grown 5 → 50 km until enough rows are in it. It is the only
way to see the unnamed rows at all.

## Building

```sh
pip install osmium                                  # pyosmium 4.x, ships wheels
./build.py liechtenstein.osm.pbf --out gaz          # places + streets + pois
./build.py liechtenstein.osm.pbf --out gaz --no-streets
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

Addresses (`addr:housenumber` + `addr:street`) are read on the same pass and
never become Python objects: a state's millions of them live in four `array`
columns per tile, 16 bytes an address, plus one interned street name each. An
address belongs to the street row of the same name (case-insensitively;
diacritics are kept) nearest within 2 km, and is dropped when there is none or
when the number has no leading integer. Per street the numbers are then
thinned and encoded as in "`street_numbers.data`" above (`street_numbers.py`,
shared with `merge.py`); `check.py` decodes every blob, and still accepts an
older file's `house_numbers` with up to 40 anchors a street.

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
./build.py liechtenstein.osm.pbf --out gaz/liechtenstein
./build.py switzerland.osm.pbf   --out gaz/switzerland
./build.py austria.osm.pbf       --out gaz/austria
./merge.py mirror gaz            # every *.gaz under gaz, grouped by tile name
./manifest.py mirror             # then the manifest, over the merged files
```

`merge.py <out_dir> <in_dir>...` searches the input directories recursively, so
one directory per extract or the flat download of a CI matrix both work. Per
tile it

* validates every input with `check.py` and stops before writing anything if
  one fails,
* drops rows that repeat an `(osm_type, osm_id)` — `(osm_type, osm_id, kind)`
  for a POI — already seen, and streets that
  repeat a name + place name + position rounded to 1e-3 degrees (~100 m),
* hands out ids from a single counter across the three tables and then the
  aliases, as `build.py` does, and remaps `admin_id` / `place_id` onto the
  surviving rows (a dropped duplicate's references go to its survivor),
* carries the aliases over with `ref_id` remapped, one row per (surviving row,
  name), and the house numbers with `street_id` remapped: each input's
  `street_numbers` points (or an older input's `house_numbers` anchors, one
  point each) are joined per surviving street, the first input winning a
  number both have. Where one input already holds all of them — a street only
  one extract saw, or two copies of one file — they are written as they are;
  only a real union of different stretches is split and thinned again, with
  the points as the truth. So merging a file with a copy of itself is a no-op,
* merges a file that predates `aliases` or the house numbers fine — it simply
  contributes none,
* keeps the higher `importance` of a row and its dropped duplicates (an input
  without the column contributes NULL),
* rebuilds the FTS index from the names, transliterated whether or not an
  input's own index was, and `vocab`, writes `meta` (`source` is the
  comma-joined distinct sources of the inputs, `has_streets` / `has_pois` are
  set when any input has them, `search_script` is `latin`) and `VACUUM`s.

A tile only one input holds goes through the same path, so the output is always
canonical. `merge.py` uses the standard library only — the merge job needs no
pyosmium.

## Fixtures

`fixtures/fixtures.sha256` pins both files.

| File | Built from | Content | Size |
|---|---|---|---:|
| `E5_N45.gaz` | `liechtenstein.osm.pbf` | 99 places (30 with `importance`), 1,315 streets, 926 pois (301 unnamed, 156 with `importance`), 139 aliases, 986 `street_numbers` rows (6,578 points of 12,226 addresses), 2,003 `vocab` terms, `search_script` `latin` | 290,816 B |
| `W20_N30.gaz` | `portugal-latest.osm.pbf`, `--tiles W20_N30` | 1,774 places, 8,435 streets, 6,501 pois, 3,234 `house_numbers` anchors, no `vocab` | 1,490,944 B |

`E5_N45.gaz` by page share: `pois` 18%, `streets` 17%, `street_numbers` 16%,
the FTS index 14%, `vocab` 13%, `idx_pois_pos` 7%, `places` 4%, everything
else (including `aliases` and its index) one page each.

```sh
./build.py liechtenstein.osm.pbf --out fixtures
./build.py portugal-latest.osm.pbf --out fixtures --tiles W20_N30
(cd fixtures && sha256sum E5_N45.gaz W20_N30.gaz > fixtures.sha256)
```

Liechtenstein covers all three kinds and plenty of umlauts to prove the
tokenizer folds them: `muhleholz` finds the village `Mühleholz` and the street
`Im Mühleholz`, `vad` puts the town `Vaduz` first, `grauspitz` finds two peaks.
It also covers the landmarks: `Rathaus Vaduz` is a `building`, `Kathedrale St.
Florin` a `place_of_worship`, `Schloss Vaduz` a `historic` built from a
multipolygon relation. `Liechtensteinisches Landesmuseum Vaduz` carries the
`name:en` the alias test looks for, and `Landstrasse` in Triesen is the street
with the most house-number points (78). It also covers the unnamed rows: 97
nameless water stops, 77 shelters, 63 bike stands, 42 toilets, 19 picnic sites, 2 charging
stations and 1 repair station, node 12899110144 a `drinking_water=no` spring
that is dropped, node 4759689350 a toilet with a tap that is two rows.
`--no-streets` is 172,032 B.
Madeira is `W20_N30`, the tile the integration tests already mirror, and holds
`Funchal`; Portugal is the only Geofabrik extract that covers it, so the
mainland tiles are discarded with `--tiles`. `W20_N30.gaz` was built before
`idx_streets_pos` was dropped, `street_numbers` replaced `house_numbers`,
`vocab` was added and the index was transliterated (no `importance`, no
`search_script`), and is kept that way on purpose: it is what proves the tools
still read an older file.

Run the tests from the repo root:

```sh
GAZ_EXTRACT=/path/to/liechtenstein.osm.pbf \
  python -m unittest tools/gazetteer/test_gazetteer.py
```

119 tests, about eight seconds (the `TestsetTest` ones run off the committed fixture and need no extract). `.github/workflows/app.yml`'s `gazetteer` job
runs exactly that on every push — it fetches the extract from Geofabrik as
`liechtenstein.osm.pbf` (the name ends up in `meta.source`, which the tests
assert on) — then `check.py` and `sha256sum -c fixtures.sha256` over the
committed fixtures. `.github/workflows/gazetteer-perf.yml` times the app's
search against New York nightly; see `app/test/perf/gazetteer_perf_test.dart`.

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
`VACUUM`. Every size below predates Addendum 4 and is that much too big: the
full New York tile `W75_N40` (607k streets, 1.17 M anchors) was 89 MB with
`idx_streets_pos` and a tenth-number anchor, and Liechtenstein went 286,720 →
249,856 B, most of it the dropped index.

| Extract | PBF | Tile | places | pois | streets | `--no-streets` | Default |
|---|---:|---|---:|---:|---:|---:|---:|
| liechtenstein | 3.5 MB | `E5_N45` | 98 | 922 | 1,313 | 0.16 MB | 0.29 MB |
| malta | 8.9 MB | `E10_N35` | 685 | 4,098 | 9,562 | — | 1.36 MB |
| iceland | 65 MB | `W25_N60` | 366 | 851 | — | 0.14 MB | — |
| berlin | 99 MB | `E10_N50` | 598 | 4,052 | 20,830 | 0.40 MB | 1.75 MB |
| portugal | 423 MB | `W20_N30` | 1,769 | 1,022 | — | 0.26 MB | — |
| new-york | 496 MB | `W75_N40` | 3,789 | 12,437 | 160,958 | 1.23 MB | 11.41 MB |

| Extract | Wall, `--no-streets` | Wall, default | Peak RSS |
|---|---:|---:|---:|
| liechtenstein | 0.9 s | 1.2 s | 61 MB |
| malta | 5.0 s | 7.0 s | 91 MB |
| iceland | 4 s | — | 299 MB |
| berlin | 11 s | 22 s | 247 MB |
| portugal | 36 s | — | 969 MB |
| new-york | 55 s | 77 s | 1.07 GB |

Collecting the addresses costs nothing worth measuring: peak RSS went 61 → 61 MB
on liechtenstein (12,560 addresses) and 89 → 91 MB on malta (3,886), because an
address is 16 bytes in an `array` and is grouped for thinning by one more
`array` of row indexes per street.

Only the liechtenstein and malta rows were measured after landmarks and areas landed;
the four bigger extracts are from before and their `pois` and sizes are now
low by roughly 3–6× on POIs and 2–3× on the default file. Roughly 3–5 MB of
PBF per second on one core now that every file is read twice. Streets are
still the whole size question: without them the densest tile measured here is 1.2 MB against a
119 MB `.rd5`, with them 11.4 MB. The New York extract covers less than half of
`W75_N40`; a complete build of that tile from `us-northeast` was ~78 MB under
the old schema and lands near 40 MB under this one, all of it streets.

### House numbers and `vocab`

Geofabrik extracts of 2026-10-04, the builder before and after `street_numbers`
replaced `house_numbers` and `vocab` was added (bytes are `dbstat` pages):

| Extract | Tile | Addresses on a street | File before → after | `house_numbers` | `street_numbers` | `vocab` |
|---|---|---:|---:|---:|---:|---:|
| liechtenstein | `E5_N45` | 12,226 | 249,856 → 286,720 B | 45,056 B | 45,056 B (986 rows) | 36,864 B |
| luxembourg | `E5_N45` | 163,879 | 2,199,552 → 2,338,816 B | 397,312 B | 356,352 B (9,020 rows) | 180,224 B |
| luxembourg | `E5_N50` | 6,752 | 217,088 → 245,760 B | 28,672 B | 28,672 B (616 rows) | 28,672 B |
| berlin | `E10_N50` | 451,698 | 6,946,816 → 7,532,544 B | 753,664 B | 847,872 B (15,632 rows) | 491,520 B |

`street_numbers` is 1.9–2.2 B an address on the two big tiles; most of the
growth is `vocab`. Distance from each address (first of its number) to where
the file puts its number:

| Extract | | median | p90 | p99 | max |
|---|---|---:|---:|---:|---:|
| liechtenstein | anchors | 29.4 m | 82.4 m | 221.6 m | 1,934 m |
| | `street_numbers` | 0.5 m | 13.9 m | 19.2 m | 20.0 m |
| luxembourg | anchors | 24.7 m | 91.1 m | 249.9 m | 1,335 m |
| | `street_numbers` | 2.8 m | 12.3 m | 18.6 m | 20.0 m |
| berlin | anchors | 30.3 m | 123.9 m | 338.8 m | 1,774 m |
| | `street_numbers` | 1.1 m | 13.0 m | 19.0 m | 20.0 m |

### Second Cyrillic spelling and language aliases

Geofabrik extracts of 2026-10-06, the builder before and after both (bytes
are `dbstat` pages; `aliases` includes its index):

| Extract | Tile | File | `search_data` | `vocab` | `aliases` | alias rows | terms |
|---|---|---:|---:|---:|---:|---:|---:|
| bulgaria | `E20_N40` | 6,537,216 → 6,623,232 B | 798,720 → 815,104 B | 352,256 → 368,640 B | 1,081,344 → 1,134,592 B | 29,193 → 30,637 | 24,843 → 26,151 |
| bulgaria | `E25_N40` | 4,743,168 → 4,837,376 B | 577,536 → 598,016 B | 258,048 → 274,432 B | 712,704 → 770,048 B | 19,843 → 21,353 | 18,163 → 19,476 |
| ile-de-france | `E0_N45` | 20,606,976 → 20,893,696 B | 3,031,040 → 3,096,576 B | 651,264 → 712,704 B | 348,160 → 507,904 B | 7,450 → 11,107 | 47,752 → 51,687 |

The growth is the language names. On `E20_N40` 20 of 86,853 names get the
second spelling: 10 language aliases and 10 Bulgarian names that write a Roman
numeral with Cyrillic `І` (`Цар Борис ІІІ`). Paris gets 81 aliases (one old,
80 language names), Sofia 52.

## Search quality

How well the app's search finds what was typed is measured, not guessed:
`testset/` holds the queries and `app/test/search_quality/` scores them
against real tiles, per tile and per kind of mistake. A change to the query
building, the spelling pass, the ranking or the file format is judged by the
difference it makes to that table.

`testset/generated/<TILE>.json` is `testset.py`'s output for eleven tiles:
real rows sampled from the file and corrupted one way each — a swapped,
missing, doubled, neighbouring-key or wrong letter, dropped accents, ß↔ss,
case, an abbreviation (`Straße`→`Str.`, `Street`→`St`, `Rua`→`R.`, …, a table
applied only where the word occurs), a compound split or two words joined, the
first or last word only, a prefix, an address with the number before or after
the street, with a letter, as a range, with the place name or with the street
abbreviated, an alias, and the untouched name as the control. Each case is
tagged with its kind and carries `near`, the row's position moved a few
kilometres, so distance ranking is scored too. Letter-based and seeded: the
same file and seed give the same file back.

```sh
./testset.py fixtures/E5_N45.gaz ~/.cache/velorki-tiles/gaz/W75_N40.gaz --out testset/generated
```

`testset/handwritten.json` is one or two addresses and landmarks per country
and address format (12/3, 12 bis, 2º, 175-II, 92-10, directionals, Cyrillic,
landmark typos); `testset/public.json` the few cases adopted from other
geocoders' suites, with `testset/SOURCES.md` saying what and under which
licence. Both give the expected row as name and position; the scorer matches
by folded name within 300 m (3 km for a street, one row per place it crosses),
never by id, so they survive a rebuilt tile.

```sh
cd app && flutter test test/search_quality --dart-define=VELORKI_GAZ_DIR=$HOME/.cache/velorki-tiles/gaz
```

Skipped without `VELORKI_GAZ_DIR`. Every `<TILE>.gaz` in the directory is
scored alone over its own cases; the table (`SEARCHQ |` lines: top 1, top 3,
top 10 and mean rank per kind) goes to stdout and the full result with every
case's rank to `app/build/search_quality/<TILE>.json`. A low score never fails
the test. The tiles come off the mirror (`latest.json` → shard `manifest.json`
→ `<TILE>.gaz`); `W20_N30` and `E5_N45` are the fixtures.

## What is missing versus Photon

Photon is a full geocoder; this is a search box that works on a plane.

* **Exact house numbers.** Only the points that keep every mapped number within
  20 m are stored; the letter is dropped (`12a` is `12`, first address wins),
  and a number past the mapped ones is the nearest end, marked approximate.
* **Fuzzy matching beyond the letters.** Typos, abbreviations and compounds
  are read from the index's own words (see the query contract); sounds-alike
  spellings are not.
* **Transliteration beyond Cyrillic and Greek.** Letter by letter, Greek and
  most Cyrillic in one spelling, Ukrainian (і, ї, є, ґ) in two; any other romanisation is left to the
  typo pass. Han, Kana, Hangul, Arabic, Hebrew, Georgian, Armenian and the
  Indic scripts are indexed as written, so they match only typed in their
  own script.
* **Admin hierarchy.** `admin_id` and `place_id` are geometry, not boundaries,
  and stop at the tile edge. No country, state or district, so Springfield,
  Massachusetts cannot be told from Springfield, Illinois.
* **Anything outside places, streets and the 43 POI kinds** — squares, rivers,
  general shops, individual addresses.
* **Language variants of ordinary rows.** `name:en` and the five other
  alternative-name tags are indexed everywhere; the rest of `name:<lang>` only
  on places with `importance` and POIs with at least 10, because on a national
  extract it is the primary name again on every object.

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
that size yet. Streets planet-wide would also need the street list spilled to
disk during the build, which is not written; `--no-streets` is the way out on a
runner that cannot hold one.
