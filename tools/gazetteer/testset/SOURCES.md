# Where the test set comes from

`generated/<TILE>.json` is made by `../testset.py` from the tile named in the
file (OpenStreetMap data via the `.gaz` build; © OpenStreetMap contributors,
ODbL). `handwritten.json` was written for this repository. `public.json` holds
the cases adopted from other geocoders' test suites, listed here with what was
taken; nothing was imported in bulk, and every case was re-pointed at a row of
our own tiles.

| Source | Licence | Taken |
|---|---|---|
| [Pelias acceptance-tests](https://github.com/pelias/acceptance-tests) (`test_cases/*.json`) | MIT (`package.json`) | the structure ideas — a focus point per query (`near`), "expected within the first N results" (`priorityThresh` → our top 1/3/10), per-locale files with a `normalizers` list (→ our `kind` tag and name folding) — and 22 query strings from `search.json`, `search_poi.json`, `french_addresses.json`, `international.json`, `search_alphanumeric_housenumber.json`, `autocomplete_streets.json`, `search_abbreviations.json`, `search_spelling_mistakes.json` that fall inside our tiles (New York, Paris, Berlin, Madrid, Rome, London, Amsterdam) |
| [libpostal](https://github.com/openvenues/libpostal) (`test/test_parser.c`, `test/test_expand.c`) | MIT | 6 New York addresses the parser is tested on (Brooklyn and Queens, with floors, suites, postcodes and the hyphenated Queens house number), used here as queries for the street they name |
| [Nominatim](https://github.com/osm-search/Nominatim) (`test/bdd/features/api/search/queries.feature`) | GPL-3.0 | ideas only, no cases: "a house number that is not mapped falls back to the road", "house number 0", a place rather than a street with a number |

Expected positions in `handwritten.json` and `public.json` were read off the
`tiles-20261001` snapshot of the mirror (`fixtures/` for `E5_N45` and
`W20_N30`); a rebuilt tile moves a row by metres, which is why the scorer
matches by name and distance, not by id.
