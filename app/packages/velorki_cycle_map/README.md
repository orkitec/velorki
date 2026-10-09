# velorki_cycle_map

The offline cycle map: which ways have bike infrastructure, cycle routes,
contraflow, surface and barriers, read out of the BRouter rd5 tiles the app
downloads for routing. Pure Dart, no Flutter.

- `Rd5CellReader` walks one cell (1/32°) of a tile through `brouter_dart`'s
  public API: each link is stored once forward, with its way's tags and its
  geometry. Tags are decoded once per distinct description.
- `classifyWay` / `classifyNode` turn tags into packed `CycleAttrs` bits.
- `mergeLines` joins links that continue one another; `simplifyLine` thins
  them per zoom; `GeoJsonWriter` writes compact GeoJSON.
- `CycleMapEngine` answers a box and zoom with GeoJSON, behind three caches:
  GeoJSON pieces per cell, zoom and content; decoded cells in memory; decoded
  cells on disk (`CellStore`, one directory per tile version, pruned when a
  tile changes). Bump `CellStore.formatVersion` when the classification
  changes.
- `CycleMapWorker` runs the engine in an isolate and writes each map to a
  file the map loads itself, so the text never reaches the UI isolate.

The way tags come from `app/assets/brouter/profiles/lookups.dat`; names,
widths and POIs are not in the tiles.

`dart run tool/survey.dart <rd5> <lon> <lat> [km]` prints what a box holds,
with timings. `dart run tool/climb_eval.dart [rule]` prints the steep length
found per grade in flat, hilly and high-rise cities (tiles from the mirror in
`~/.cache/velorki-tiles/`), for tuning `ClimbRule`: the heights include
buildings in city centres, and the rule has to keep Manhattan and Cologne
quiet while Lausanne, San Francisco and Funchal keep their hills.
