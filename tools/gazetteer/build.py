#!/usr/bin/env python3
"""Build per-tile offline gazetteer files from an OSM PBF extract.

One SQLite file comes out per 5 degree BRouter tile the extract touches, named
after the tile (``gaz/W75_N40.gaz``), so a phone can download the search data
for exactly the tiles it already has routing data for. The file format is
version 1 of the Velorki gazetteer; see README.md for the schema.

Default content is places plus named points of interest, which keeps every
tile to a few MB. Streets are opt-in (``--streets``) and roughly quadruple the
file.

The PBF is streamed, never loaded whole. Node coordinates go through an osmium
location cache (in memory for small extracts, a file on disk for big ones), so
Python only ever sees the objects that carry tags worth keeping. Areas are
assembled as well, which costs a second pass over the file and is what makes a
lake, a park or a big building mapped as a multipolygon relation searchable.

Usage:
    build.py liechtenstein.osm.pbf --out gaz
    build.py liechtenstein.osm.pbf --out gaz --streets
"""

from __future__ import annotations

import argparse
import math
import os
import sqlite3
import sys
import tempfile
import time
from collections import defaultdict
from datetime import datetime, timezone
from typing import Iterable, NamedTuple

import osmium
import osmium.filter as osmium_filter

SCHEMA_VERSION = 1

TILE_SIZE_DEG = 5

# Coordinates are stored as integers in 1e-7 degrees: half the bytes of a
# SQLite REAL, and still 1 cm of resolution.
COORD_SCALE = 1e7

# The place values worth putting in a search box. Anything bigger (country,
# state) is not something a rider types to plan a ride, anything smaller is
# noise.
PLACE_KINDS = frozenset(
    "city town village hamlet suburb neighbourhood locality island".split()
)

# Places that can be the "which town is this in" context of a smaller place.
CONTEXT_KINDS = frozenset("city town".split())

# What a rider needs on the road, and what a rider searches for by name.
# Unnamed objects are dropped throughout: a search box cannot find a row with
# no name.
#
# The first group is the rider's own kit; it is matched first so a café in a
# historic building stays a café.
POI_AMENITIES = {
    "drinking_water": "drinking_water",
    "cafe": "cafe",
    "bicycle_repair_station": "bicycle_repair_station",
    "shelter": "shelter",
}

# The second group is landmarks: what somebody types into the search box as a
# destination. Matched in the order below, so the more specific kind wins and
# `building` is only ever the fallback.
MUSEUM_TOURISM = frozenset("museum gallery".split())
ATTRACTION_TOURISM = frozenset("attraction theme_park zoo aquarium".split())
HOSPITAL_AMENITIES = frozenset("hospital clinic".split())
UNIVERSITY_AMENITIES = frozenset("university college".split())
STADIUM_LEISURE = frozenset("stadium sports_centre ice_rink swimming_pool".split())
MALL_SHOPS = frozenset("mall department_store".split())
TOWER_MAN_MADE = frozenset(
    "tower communications_tower observation_tower mast".split()
)
WATER_NATURAL = frozenset("water bay strait lagoon".split())
RESERVE_BOUNDARIES = frozenset("national_park protected_area".split())

# Street grouping: a street with no place to hang off gets grouped by a coarse
# grid cell instead, so two "Main Street"s in villages 40 km apart do not
# collapse into one row at a meaningless midpoint.
ORPHAN_CELL_DEG = 0.1

# How far a street or POI may look for the place it belongs to.
PLACE_RADIUS_M = 5000.0

# How far a smaller place may look for the town it sits in.
CONTEXT_RADIUS_M = 25000.0

# Nearest-neighbour lookups bucket places into a grid this wide. 0.05 degrees
# of latitude is about 5.5 km, so a 5 km search only has to look at the
# neighbouring cells.
GRID_DEG = 0.05

METERS_PER_DEG_LAT = 111320.0


# --------------------------------------------------------------------------
# tiles
# --------------------------------------------------------------------------


def tile_name(lat: float, lon: float) -> str:
    """The BRouter tile name for a coordinate, matching tiles.dart."""
    lat0 = min(85, max(-90, math.floor(lat / TILE_SIZE_DEG) * TILE_SIZE_DEG))
    lon0 = min(175, max(-180, math.floor(lon / TILE_SIZE_DEG) * TILE_SIZE_DEG))
    ns = "S" if lat0 < 0 else "N"
    ew = "W" if lon0 < 0 else "E"
    return f"{ew}{abs(lon0)}_{ns}{abs(lat0)}"


# --------------------------------------------------------------------------
# small helpers
# --------------------------------------------------------------------------


def parse_population(raw: str | None) -> int | None:
    """OSM population values are often '1 234' or '~5000'; keep the digits."""
    if not raw:
        return None
    digits = "".join(c for c in raw if c.isdigit())
    if not digits or len(digits) > 12:
        return None
    return int(digits)


def meters_between(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Flat-earth distance. Good enough over the few km these lookups span."""
    dlat = (lat1 - lat2) * METERS_PER_DEG_LAT
    dlon = (lon1 - lon2) * METERS_PER_DEG_LAT * math.cos(math.radians(lat1))
    return math.hypot(dlat, dlon)


def clean_name(raw: str | None) -> str | None:
    if not raw:
        return None
    name = " ".join(raw.split())
    if not name or len(name) > 200:
        return None
    return name


def scaled(value: float) -> int:
    return int(round(value * COORD_SCALE))


# --------------------------------------------------------------------------
# reading the PBF
# --------------------------------------------------------------------------


class RawPlace(NamedTuple):
    name: str
    kind: str
    lat: float
    lon: float
    population: int | None
    context: str | None  # is_in / addr:city, a name, not yet an id
    osm_type: str  # 'n', 'w' or 'r'
    osm_id: int


class RawStreet(NamedTuple):
    name: str
    addr_city: str | None
    lat: float
    lon: float


class RawPoi(NamedTuple):
    name: str
    kind: str
    lat: float
    lon: float
    osm_type: str
    osm_id: int


class Extract(NamedTuple):
    places: list[RawPlace]
    street_ways: list[RawStreet]
    pois: list[RawPoi]


def poi_kind(tags) -> str | None:
    """The one kind an object gets, or None if it is not worth a row.

    First match wins, so the order is the priority: the rider's kit, then
    landmarks from most to least specific, then `building` as the fallback for
    anything else that carries a name.
    """
    amenity = tags.get("amenity")
    shop = tags.get("shop")
    tourism = tags.get("tourism")
    natural = tags.get("natural")
    leisure = tags.get("leisure")

    # --- the rider's kit -------------------------------------------------
    if amenity in POI_AMENITIES:
        return POI_AMENITIES[amenity]
    if shop == "bicycle":
        return "bicycle_shop"
    if tags.get("railway") == "station":
        return "station"
    if tourism == "viewpoint":
        return "viewpoint"
    if natural == "peak":
        return "peak"
    if leisure == "park":
        return "park"

    # --- landmarks -------------------------------------------------------
    if tourism in ATTRACTION_TOURISM:
        return "attraction"
    if tourism in MUSEUM_TOURISM:
        return "museum"
    # historic=yes says nothing on its own, so it only counts when no other
    # kind fits; any real historic=* value wins over the kinds below it.
    historic = tags.get("historic")
    if historic and historic != "yes":
        return "historic"
    if amenity == "place_of_worship":
        return "place_of_worship"
    if amenity in HOSPITAL_AMENITIES:
        return "hospital"
    if amenity in UNIVERSITY_AMENITIES:
        return "university"
    if leisure in STADIUM_LEISURE:
        return "stadium"
    if shop in MALL_SHOPS:
        return "mall"
    if tags.get("aeroway") == "aerodrome":
        return "airport"
    if amenity == "ferry_terminal":
        return "ferry_terminal"
    man_made = tags.get("man_made")
    if man_made == "lighthouse":
        return "lighthouse"
    if man_made in TOWER_MAN_MADE:
        return "tower"
    if natural in WATER_NATURAL or tags.get("landuse") == "reservoir":
        return "water"
    if natural == "beach":
        return "beach"
    if leisure == "nature_reserve" or tags.get("boundary") in RESERVE_BOUNDARIES:
        return "nature_reserve"
    if historic == "yes":
        return "historic"

    # --- anything else with a name and four walls ------------------------
    building = tags.get("building")
    if building and building != "no":
        return "building"
    return None


def is_bare_number(name: str) -> bool:
    """True for a `name` with no letter in it at all.

    That is a house number somebody typed into the name field, or a numbered
    boundary stone. Nobody searches for '12', and the FTS index would answer
    such a query with hundreds of them.
    """
    return not any(character.isalpha() for character in name)


def way_centroid(way) -> tuple[float, float] | None:
    """Mean of a way's node coordinates, skipping nodes the cache missed."""
    total_lat = 0.0
    total_lon = 0.0
    count = 0
    for node in way.nodes:
        if not node.location.valid():
            continue
        total_lat += node.location.lat
        total_lon += node.location.lon
        count += 1
    if count == 0:
        return None
    return total_lat / count, total_lon / count


def area_centroid(area) -> tuple[float, float] | None:
    """Mean of the nodes of an area's outer rings.

    Good enough to put a lake or a shopping centre in the right tile and on the
    right spot on the map; holes and ring areas are not worth a polygon
    centroid here.
    """
    total_lat = 0.0
    total_lon = 0.0
    count = 0
    for ring in area.outer_rings():
        for node in ring:
            if not node.location.valid():
                continue
            total_lat += node.location.lat
            total_lon += node.location.lon
            count += 1
    if count == 0:
        return None
    return total_lat / count, total_lon / count


def read_pbf(path: str, want_streets: bool, node_cache: str) -> Extract:
    # Keyed by OSM identity: a closed way arrives twice, once as the way and
    # once as the area osmium assembles from it, and the area wins.
    places: dict[tuple[str, int], RawPlace] = {}
    pois: dict[tuple[str, int], RawPoi] = {}
    street_ways: list[RawStreet] = []
    intern = sys.intern

    processor = (
        osmium.FileProcessor(
            path, osmium.osm.NODE | osmium.osm.WAY | osmium.osm.AREA
        )
        # Areas cost a second pass over the file: osmium indexes the
        # multipolygon and boundary relations first, then assembles each one
        # while the ways stream past. Without this a lake, a park or a big
        # building mapped as a relation is simply missing.
        .with_areas()
        .with_locations(node_cache)
        # Untagged nodes never reach Python; they only feed the location cache.
        .with_filter(osmium_filter.EmptyTagFilter())
    )

    for obj in processor:
        tags = obj.tags
        name = clean_name(tags.get("name"))
        if not name:
            continue
        is_area = isinstance(obj, osmium.osm.Area)
        is_node = isinstance(obj, osmium.osm.Node)

        place = tags.get("place")
        want_place = place in PLACE_KINDS
        want_street = want_streets and not is_node and not is_area and "highway" in tags
        kind = poi_kind(tags)
        if kind and is_bare_number(name):
            kind = None
        if not (want_place or want_street or kind):
            continue

        # One representative point per object: the node itself, the mean of a
        # way's nodes, or the mean of an assembled area's outer rings.
        if is_node:
            if not obj.location.valid():
                continue
            lat, lon = obj.location.lat, obj.location.lon
        else:
            point = area_centroid(obj) if is_area else way_centroid(obj)
            if point is None:
                continue
            lat, lon = point

        # The OSM identity travels with the row so two extracts that overlap
        # can be merged without counting the same object twice. An area keeps
        # the identity of what it was built from: the relation, or the way.
        if is_area:
            osm_type = "w" if obj.from_way() else "r"
            osm_id = obj.orig_id()
        else:
            osm_type = "n" if is_node else "w"
            osm_id = obj.id
        key = (osm_type, osm_id)

        if want_place and (is_area or key not in places):
            places[key] = RawPlace(
                name,
                intern(place),
                lat,
                lon,
                parse_population(tags.get("population")),
                clean_name(
                    tags.get("is_in:city")
                    or tags.get("addr:city")
                    or tags.get("is_in")
                ),
                osm_type,
                osm_id,
            )

        # Streets come from ways only; a named highway node is a bus stop or a
        # crossing, not a street, and a pedestrian area is already the way.
        if want_street:
            city = clean_name(tags.get("addr:city"))
            street_ways.append(
                RawStreet(intern(name), intern(city) if city else None, lat, lon)
            )

        if kind and (is_area or key not in pois):
            pois[key] = RawPoi(name, kind, lat, lon, osm_type, osm_id)

    return Extract(list(places.values()), street_ways, list(pois.values()))


# --------------------------------------------------------------------------
# nearest-place lookups, within one tile
# --------------------------------------------------------------------------


class PlaceRow(NamedTuple):
    id: int
    name: str
    kind: str
    lat: float
    lon: float
    population: int | None
    admin_id: int | None
    osm_type: str | None
    osm_id: int | None


class PlaceGrid:
    """Bucketed places so 'nearest place' does not turn into a full scan."""

    def __init__(self, places: Iterable[PlaceRow], kinds: frozenset[str] | None = None):
        self.cells: dict[tuple[int, int], list[PlaceRow]] = defaultdict(list)
        for place in places:
            if kinds is not None and place.kind not in kinds:
                continue
            self.cells[self._cell(place.lat, place.lon)].append(place)

    @staticmethod
    def _cell(lat: float, lon: float) -> tuple[int, int]:
        return int(math.floor(lat / GRID_DEG)), int(math.floor(lon / GRID_DEG))

    def nearest(
        self, lat: float, lon: float, radius_m: float, skip_id: int | None = None
    ) -> PlaceRow | None:
        span = max(1, int(math.ceil(radius_m / (GRID_DEG * METERS_PER_DEG_LAT))) + 1)
        cell_lat, cell_lon = self._cell(lat, lon)
        best: PlaceRow | None = None
        best_distance = radius_m
        for dlat in range(-span, span + 1):
            for dlon in range(-span, span + 1):
                for place in self.cells.get((cell_lat + dlat, cell_lon + dlon), ()):
                    if place.id == skip_id:
                        continue
                    distance = meters_between(lat, lon, place.lat, place.lon)
                    if distance < best_distance:
                        best_distance = distance
                        best = place
        return best


def resolve_places(raw: list[RawPlace], first_id: int) -> list[PlaceRow]:
    """Give places ids and fill admin_id with the town or city they sit in.

    admin_id can only point at a place in the same file, so a village whose
    nearest town falls in the neighbouring tile keeps a NULL.
    """
    rows = [
        PlaceRow(
            first_id + index,
            p.name,
            p.kind,
            p.lat,
            p.lon,
            p.population,
            None,
            p.osm_type,
            p.osm_id,
        )
        for index, p in enumerate(raw)
    ]
    towns = PlaceGrid(rows, CONTEXT_KINDS)
    by_name: dict[str, list[PlaceRow]] = defaultdict(list)
    for row in rows:
        if row.kind in CONTEXT_KINDS:
            by_name[row.name].append(row)

    out: list[PlaceRow] = []
    for row, source in zip(rows, raw):
        admin_id: int | None = None
        if row.kind not in CONTEXT_KINDS:
            # is_in / addr:city names the town when OSM has it, but only a town
            # that is actually nearby; otherwise fall back to pure geometry.
            named = [
                candidate
                for candidate in by_name.get(source.context or "", ())
                if meters_between(row.lat, row.lon, candidate.lat, candidate.lon)
                <= CONTEXT_RADIUS_M
            ]
            if named:
                admin_id = min(
                    named,
                    key=lambda c: meters_between(row.lat, row.lon, c.lat, c.lon),
                ).id
            else:
                near = towns.nearest(row.lat, row.lon, CONTEXT_RADIUS_M, row.id)
                if near is not None:
                    admin_id = near.id
        out.append(row._replace(admin_id=admin_id))
    return out


def place_of(
    lat: float,
    lon: float,
    addr_city: str | None,
    grid: PlaceGrid,
    by_name: dict[str, list[PlaceRow]],
) -> int | None:
    """The place a street or POI belongs to: addr:city, else nearest in 5 km."""
    if addr_city:
        named = by_name.get(addr_city)
        if named:
            return min(
                named, key=lambda c: meters_between(lat, lon, c.lat, c.lon)
            ).id
    near = grid.nearest(lat, lon, PLACE_RADIUS_M)
    return near.id if near is not None else None


class StreetRow(NamedTuple):
    id: int
    name: str
    lat: float
    lon: float
    place_id: int | None


def merge_streets(
    ways: list[RawStreet],
    grid: PlaceGrid,
    by_name: dict[str, list[PlaceRow]],
    first_id: int,
) -> list[StreetRow]:
    """One row per street name per place, at the centre of its ways."""
    groups: dict[tuple, list[float]] = {}
    for way in ways:
        place_id = place_of(way.lat, way.lon, way.addr_city, grid, by_name)
        if place_id is not None:
            key: tuple = (way.name, place_id, 0, 0)
        else:
            # No place anywhere near: group by a coarse cell so distant
            # same-named rural roads stay separate rows.
            key = (
                way.name,
                None,
                int(math.floor(way.lat / ORPHAN_CELL_DEG)),
                int(math.floor(way.lon / ORPHAN_CELL_DEG)),
            )
        bucket = groups.get(key)
        if bucket is None:
            groups[key] = [way.lat, way.lon, 1.0]
        else:
            bucket[0] += way.lat
            bucket[1] += way.lon
            bucket[2] += 1.0

    return [
        StreetRow(
            first_id + index,
            key[0],
            value[0] / value[2],
            value[1] / value[2],
            key[1],
        )
        for index, (key, value) in enumerate(groups.items())
    ]


# --------------------------------------------------------------------------
# writing one tile
# --------------------------------------------------------------------------

SCHEMA = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);

CREATE TABLE places (
    id         INTEGER PRIMARY KEY,
    name       TEXT NOT NULL,
    kind       TEXT NOT NULL,
    lat        INTEGER NOT NULL,
    lon        INTEGER NOT NULL,
    population INTEGER,
    admin_id   INTEGER,
    osm_type   TEXT,
    osm_id     INTEGER
);

CREATE TABLE streets (
    id       INTEGER PRIMARY KEY,
    name     TEXT NOT NULL,
    lat      INTEGER NOT NULL,
    lon      INTEGER NOT NULL,
    place_id INTEGER,
    osm_type TEXT,
    osm_id   INTEGER
);

CREATE TABLE pois (
    id       INTEGER PRIMARY KEY,
    name     TEXT NOT NULL,
    kind     TEXT NOT NULL,
    lat      INTEGER NOT NULL,
    lon      INTEGER NOT NULL,
    place_id INTEGER,
    osm_type TEXT,
    osm_id   INTEGER
);

-- One id space across the three tables, so an FTS rowid names exactly one row
-- in exactly one table and a hit is hydrated with three primary-key lookups.
-- A UNION ALL view reads better but SQLite materialises it on every query.
--
-- Contentless: the names already live in the three tables, so a second copy
-- would be a fifth of the file. columnsize=0 drops bm25's length
-- normalisation, which buys nothing when every document is one short name.
-- No prefix= option: measured slower at every query length and 14 MB bigger
-- on a dense tile.
CREATE VIRTUAL TABLE search USING fts5(
    name,
    content='',
    columnsize=0,
    tokenize='unicode61 remove_diacritics 2'
);

-- osm_type ('n', 'w', 'r') and osm_id carry the OSM identity of a row, so
-- merge.py can drop the duplicates two overlapping extracts produce. A street
-- is merged out of many ways and has no single identity, so it keeps NULLs and
-- merge.py falls back to name + place + rounded position for those.
--
-- Reverse lookup is a bounding box on lat/lon plus a sort, so a plain index on
-- the coordinates is all it needs.
CREATE INDEX idx_places_pos  ON places(lat, lon);
CREATE INDEX idx_streets_pos ON streets(lat, lon);
CREATE INDEX idx_pois_pos    ON pois(lat, lon);
"""


class TileStats(NamedTuple):
    tile: str
    path: str
    places: int
    streets: int
    pois: int
    bytes: int


def write_tile(
    path: str,
    tile: str,
    places: list[PlaceRow],
    streets: list[StreetRow],
    pois: list[tuple[int, str, str, float, float, int | None, str, int]],
    source: str,
    has_streets: bool,
    built_at: str,
) -> TileStats:
    if os.path.exists(path):
        os.remove(path)

    db = sqlite3.connect(path)
    db.executescript(
        "PRAGMA page_size=4096;"
        "PRAGMA journal_mode=DELETE;"
        "PRAGMA synchronous=OFF;"
    )
    db.executescript(SCHEMA)

    db.executemany(
        "INSERT INTO places (id, name, kind, lat, lon, population, admin_id,"
        " osm_type, osm_id) VALUES (?,?,?,?,?,?,?,?,?)",
        [
            (
                p.id,
                p.name,
                p.kind,
                scaled(p.lat),
                scaled(p.lon),
                p.population,
                p.admin_id,
                p.osm_type,
                p.osm_id,
            )
            for p in places
        ],
    )
    # A street row is the mean of many ways, so it has no OSM identity of its
    # own: osm_type and osm_id stay NULL and merge.py matches it by position.
    db.executemany(
        "INSERT INTO streets (id, name, lat, lon, place_id, osm_type, osm_id)"
        " VALUES (?,?,?,?,?,NULL,NULL)",
        [(s.id, s.name, scaled(s.lat), scaled(s.lon), s.place_id) for s in streets],
    )
    db.executemany(
        "INSERT INTO pois (id, name, kind, lat, lon, place_id, osm_type, osm_id)"
        " VALUES (?,?,?,?,?,?,?,?)",
        [
            (pid, name, kind, scaled(lat), scaled(lon), place_id, osm_type, osm_id)
            for pid, name, kind, lat, lon, place_id, osm_type, osm_id in pois
        ],
    )

    db.executemany(
        "INSERT INTO search(rowid, name) VALUES (?,?)",
        [(p.id, p.name) for p in places]
        + [(s.id, s.name) for s in streets]
        + [(row[0], row[1]) for row in pois],
    )

    db.executemany(
        "INSERT INTO meta VALUES (?,?)",
        [
            ("schema_version", str(SCHEMA_VERSION)),
            ("tile", tile),
            ("built_at", built_at),
            ("source", source),
            ("has_streets", "1" if has_streets else "0"),
            ("has_pois", "1"),
        ],
    )
    db.commit()
    db.execute("INSERT INTO search(search) VALUES ('optimize')")
    db.commit()
    db.execute("VACUUM")
    db.close()

    return TileStats(tile, path, len(places), len(streets), len(pois), os.path.getsize(path))


# --------------------------------------------------------------------------


def pick_node_cache(pbf: str, requested: str) -> tuple[str, str | None]:
    """Choose a location cache; big extracts get one on disk, not in RAM."""
    if requested != "auto":
        return requested, None
    if os.path.getsize(pbf) < 150 * 1024 * 1024:
        return "flex_mem", None
    handle, temp = tempfile.mkstemp(suffix=".nodecache")
    os.close(handle)
    os.remove(temp)
    return f"sparse_file_array,{temp}", temp


def build_tile(
    out_dir: str,
    tile: str,
    raw_places: list[RawPlace],
    raw_streets: list[RawStreet],
    raw_pois: list[RawPoi],
    source: str,
    has_streets: bool,
    built_at: str,
) -> TileStats:
    places = resolve_places(raw_places, 1)
    grid = PlaceGrid(places)
    by_name: dict[str, list[PlaceRow]] = defaultdict(list)
    for place in places:
        by_name[place.name].append(place)

    next_id = len(places) + 1
    streets = merge_streets(raw_streets, grid, by_name, next_id) if has_streets else []
    next_id += len(streets)

    pois = [
        (
            next_id + index,
            poi.name,
            poi.kind,
            poi.lat,
            poi.lon,
            place_of(poi.lat, poi.lon, None, grid, by_name),
            poi.osm_type,
            poi.osm_id,
        )
        for index, poi in enumerate(raw_pois)
    ]

    return write_tile(
        os.path.join(out_dir, f"{tile}.gaz"),
        tile,
        places,
        streets,
        pois,
        source,
        has_streets,
        built_at,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pbf", help="input .osm.pbf")
    parser.add_argument("--out", default="gaz", help="output directory")
    parser.add_argument(
        "--streets",
        action="store_true",
        help="also write the street table (roughly 4x the file)",
    )
    parser.add_argument(
        "--tiles",
        default=None,
        help="comma-separated tile names to write; others are discarded",
    )
    parser.add_argument(
        "--node-cache",
        default="auto",
        help="osmium location cache: auto, flex_mem, or sparse_file_array,PATH",
    )
    parser.add_argument("--source", default=None, help="source label for the meta row")
    args = parser.parse_args()

    started = time.monotonic()
    source = args.source or os.path.basename(args.pbf)
    built_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    wanted = set(args.tiles.split(",")) if args.tiles else None
    os.makedirs(args.out, exist_ok=True)

    cache, temp_cache = pick_node_cache(args.pbf, args.node_cache)
    print(f"reading {args.pbf} (location cache: {cache.split(',')[0]})")
    try:
        extract = read_pbf(args.pbf, args.streets, cache)
    finally:
        if temp_cache and os.path.exists(temp_cache):
            os.remove(temp_cache)
    read_done = time.monotonic()
    print(
        f"  {len(extract.places)} place objects, "
        f"{len(extract.street_ways)} named highway ways, "
        f"{len(extract.pois)} named pois "
        f"in {read_done - started:.1f}s"
    )

    tiles: dict[str, tuple[list[RawPlace], list[RawStreet], list[RawPoi]]]
    tiles = defaultdict(lambda: ([], [], []))
    for place in extract.places:
        tiles[tile_name(place.lat, place.lon)][0].append(place)
    for street in extract.street_ways:
        tiles[tile_name(street.lat, street.lon)][1].append(street)
    for poi in extract.pois:
        tiles[tile_name(poi.lat, poi.lon)][2].append(poi)

    results: list[TileStats] = []
    for tile in sorted(tiles):
        if wanted is not None and tile not in wanted:
            continue
        tile_places, tile_streets, tile_pois = tiles[tile]
        results.append(
            build_tile(
                args.out,
                tile,
                tile_places,
                tile_streets,
                tile_pois,
                source,
                args.streets,
                built_at,
            )
        )

    elapsed = time.monotonic() - started
    print(f"\n{'tile':<12} {'places':>8} {'streets':>9} {'pois':>8} {'size':>10}")
    for row in results:
        print(
            f"{row.tile:<12} {row.places:>8} {row.streets:>9} "
            f"{row.pois:>8} {row.bytes / 1e6:>9.2f}M"
        )
    total = sum(r.bytes for r in results)
    print(f"{'total':<12} {'':>8} {'':>9} {'':>8} {total / 1e6:>9.2f}M")
    print(f"built in {elapsed:.1f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
