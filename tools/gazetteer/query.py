#!/usr/bin/env python3
"""Run the app's gazetteer queries from the command line.

    query.py fixtures/E5_N45.gaz muhleholz
    query.py fixtures/E5_N45.gaz vad --near 47.141,9.521
    query.py fixtures/E5_N45.gaz 12 landstrasse
    query.py fixtures/E5_N45.gaz --near 47.141,9.521 --kind drinking_water
    query.py --reverse fixtures/E5_N45.gaz 47.1410 9.5215

The forward form is exactly what the app runs: one FTS statement, then three
primary-key lookups per hit, then the ranking in Python (bm25, name length, population,
distance to `--near`). A hit that is none of the three is an alias, and is
resolved through `aliases.ref_id` to the row whose primary name is shown. A
digits-only token at the start or the end of a multi-token query is a house
number: it is taken out of the match and resolved against the street's anchors,
which prints `≈` when the position is interpolated rather than mapped.

`--kind` with `--near` skips the search box altogether and lists the rows of
one POI kind nearest to the point, named or not: that is how the app answers
"drinking water", and the only way to see the unnamed utility rows at all.

The reverse form is the nearest street, place and POI to a coordinate, found
with a bounding box on the lat/lon indexes. `streets` has no such index in a
file built today — the app never looks a street up by position — so the street
answer comes from one full scan of the table and is marked `(scan)`.
"""

from __future__ import annotations

import argparse
import math
import sqlite3
import time
from typing import NamedTuple

COORD_SCALE = 1e7
METERS_PER_DEG_LAT = 111320.0

# Take the best 60 rows out of the FTS index and hydrate them one by one. A
# UNION ALL view over the three tables reads better but SQLite materialises it
# on every query, which costs a quarter of a second on a dense tile.
SEARCH_SQL = (
    "SELECT rowid, bm25(search) AS rank FROM search "
    "WHERE search MATCH ? ORDER BY rank LIMIT 60"
)

HYDRATE = {
    "place": "SELECT name, kind, lat, lon, population, admin_id FROM places WHERE id = ?",
    "street": "SELECT name, 'street', lat, lon, NULL, place_id FROM streets WHERE id = ?",
    "poi": "SELECT name, kind, lat, lon, NULL, place_id FROM pois WHERE id = ?",
}

MIN_QUERY_CHARS = 3


class Hit(NamedTuple):
    id: int
    name: str
    kind: str
    lat: float
    lon: float
    population: int | None
    context: str | None
    rank: float
    distance_m: float | None
    house_number: str | None = None
    approximate: bool = False


def fts_query(text: str) -> str:
    """Turn what the user typed into an FTS5 prefix query.

    Every word becomes a quoted phrase so punctuation cannot break the query
    syntax, and the LAST word gets a `*` so the search fires while the user is
    still typing it.
    """
    words = [w.replace('"', '""') for w in text.split() if w.strip()]
    if not words:
        return '""'
    quoted = [f'"{w}"' for w in words]
    quoted[-1] += "*"
    return " ".join(quoted)


def place_name(db: sqlite3.Connection, place_id: int | None) -> str | None:
    if place_id is None:
        return None
    row = db.execute("SELECT name FROM places WHERE id = ?", (place_id,)).fetchone()
    return row[0] if row else None


def split_house_number(text: str) -> tuple[str, str | None]:
    """Take the house number out of the text the user typed.

    A digits-only token at the start or the end of a multi-token query is the
    number — `12 Landstrasse`, `Landstrasse 12`. `42nd` is not digits only and
    stays part of the match, and a query that is nothing but digits has no
    street left to hang the number off, so it stays a plain search.
    """
    tokens = text.split()
    if len(tokens) < 2:
        return text, None
    if tokens[0].isascii() and tokens[0].isdigit():
        return " ".join(tokens[1:]), tokens[0]
    if tokens[-1].isascii() and tokens[-1].isdigit():
        return " ".join(tokens[:-1]), tokens[-1]
    return text, None


def hydrate(db: sqlite3.Connection, rowid: int) -> tuple | None:
    """The one row an FTS rowid names, out of places, streets or pois."""
    for statement in HYDRATE.values():
        row = db.execute(statement, (rowid,)).fetchone()
        if row is not None:
            return row
    return None


def alias_ref(db: sqlite3.Connection, rowid: int) -> int | None:
    """A rowid that is in none of the three tables is an alias, or nothing."""
    try:
        row = db.execute(
            "SELECT ref_id FROM aliases WHERE id = ?", (rowid,)
        ).fetchone()
    except sqlite3.Error:
        return None  # a file built before aliases existed
    return row[0] if row else None


def anchor_position(
    db: sqlite3.Connection, street_id: int, number: int, lat: float, lon: float
) -> tuple[float, float, bool]:
    """Where house `number` is on street `street_id`, and whether that is a guess.

    An exact anchor is the real position. Otherwise the two anchors that
    bracket the number are interpolated by number; past either end the nearest
    end anchor is used; with no anchors at all the street's own centre is the
    answer. Everything but an exact anchor is approximate.
    """
    exact = db.execute(
        "SELECT lat, lon FROM house_numbers WHERE street_id = ? AND number = ?",
        (street_id, number),
    ).fetchone()
    if exact is not None:
        return exact[0] / COORD_SCALE, exact[1] / COORD_SCALE, False

    below = db.execute(
        "SELECT number, lat, lon FROM house_numbers WHERE street_id = ? AND number < ?"
        " ORDER BY number DESC LIMIT 1",
        (street_id, number),
    ).fetchone()
    above = db.execute(
        "SELECT number, lat, lon FROM house_numbers WHERE street_id = ? AND number > ?"
        " ORDER BY number ASC LIMIT 1",
        (street_id, number),
    ).fetchone()
    if below is not None and above is not None:
        share = (number - below[0]) / (above[0] - below[0])
        return (
            (below[1] + (above[1] - below[1]) * share) / COORD_SCALE,
            (below[2] + (above[2] - below[2]) * share) / COORD_SCALE,
            True,
        )
    end = below or above
    if end is not None:
        return end[1] / COORD_SCALE, end[2] / COORD_SCALE, True
    return lat, lon, True


def locate(db: sqlite3.Connection, hit: Hit, number: str) -> Hit:
    """Put a house number on a street hit; anything else keeps its own point."""
    if hit.kind != "street":
        return hit
    try:
        lat, lon, approximate = anchor_position(
            db, hit.id, int(number), hit.lat, hit.lon
        )
    except sqlite3.Error:
        return hit._replace(house_number=number, approximate=True)
    return hit._replace(
        lat=lat, lon=lon, house_number=number, approximate=approximate
    )


def search(
    db: sqlite3.Connection,
    text: str,
    limit: int,
    near: tuple[float, float] | None = None,
) -> list[Hit]:
    match_text, number = split_house_number(text)
    # An object and its aliases are separate FTS rows: two hits resolving to
    # the same row are one result, at the better of the two ranks.
    best: dict[int, Hit] = {}
    for rowid, rank in db.execute(SEARCH_SQL, (fts_query(match_text),)):
        row = hydrate(db, rowid)
        if row is None:
            ref = alias_ref(db, rowid)
            if ref is None:
                continue
            row = hydrate(db, ref)
            if row is None:
                continue
            rowid = ref
        previous = best.get(rowid)
        if previous is not None and previous.rank <= rank:
            continue
        name, kind, lat, lon, population, ref = row
        lat, lon = lat / COORD_SCALE, lon / COORD_SCALE
        distance = (
            meters_between(near[0], near[1], lat, lon) if near is not None else None
        )
        best[rowid] = Hit(
            rowid, name, kind, lat, lon, population, place_name(db, ref), rank, distance
        )

    hits = list(best.values())
    if number is not None:
        hits = [locate(db, hit, number) for hit in hits]
    hits.sort(
        key=lambda h: (
            h.rank,
            len(h.name),
            -(h.population or 0),
            h.distance_m if h.distance_m is not None else 0.0,
        )
    )
    return hits[:limit]


def meters_between(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    dlat = (lat1 - lat2) * METERS_PER_DEG_LAT
    dlon = (lon1 - lon2) * METERS_PER_DEG_LAT * math.cos(math.radians(lat1))
    return math.hypot(dlat, dlon)


# --------------------------------------------------------------------------
# nearest of a kind
# --------------------------------------------------------------------------

# What the app does when the typed text is a kind keyword ("drinking water"):
# a bounding box on idx_pois_pos, grown until enough rows are in it. Unnamed
# rows are the point of it — they are in no index but this one.
KIND_RADII_KM = (5.0, 10.0, 25.0, 50.0)


def nearest_of_kind(
    db: sqlite3.Connection, kind: str, lat: float, lon: float, limit: int
) -> list[tuple[int, str | None, float, float, int | None, float]]:
    """The `limit` rows of one POI kind nearest to a point, named or not."""
    rows: list[tuple] = []
    for radius_km in KIND_RADII_KM:
        degrees = radius_km * 1000 / METERS_PER_DEG_LAT
        dlon = degrees / max(0.05, math.cos(math.radians(lat)))
        rows = db.execute(
            "SELECT id, name, lat, lon, place_id FROM pois WHERE kind = ?"
            " AND lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
            (
                kind,
                int((lat - degrees) * COORD_SCALE),
                int((lat + degrees) * COORD_SCALE),
                int((lon - dlon) * COORD_SCALE),
                int((lon + dlon) * COORD_SCALE),
            ),
        ).fetchall()
        if len(rows) >= limit:
            break
    found = [
        (
            row[0],
            row[1],
            row[2] / COORD_SCALE,
            row[3] / COORD_SCALE,
            row[4],
            meters_between(lat, lon, row[2] / COORD_SCALE, row[3] / COORD_SCALE),
        )
        for row in rows
    ]
    found.sort(key=lambda row: row[5])
    return found[:limit]


# The reverse lookup asks the same four columns of each table; only the kind
# and the foreign key are named differently.
REVERSE_SQL = {
    "streets": "SELECT name, lat, lon, 'street', place_id FROM streets",
    "places": "SELECT name, lat, lon, kind, admin_id FROM places",
    "pois": "SELECT name, lat, lon, kind, place_id FROM pois",
}


def has_position_index(db: sqlite3.Connection, table: str) -> bool:
    """Whether `idx_<table>_pos` is in the file; `streets` has none since the trim."""
    return (
        db.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = ?",
            (f"idx_{table}_pos",),
        ).fetchone()
        is not None
    )


def nearest_by_scan(
    db: sqlite3.Connection, table: str, lat: float, lon: float
) -> tuple[tuple, float] | tuple[None, None]:
    """Nearest row without a positional index: read the table once, keep the best.

    Growing a bounding box over an unindexed table would scan it up to four
    times over; one pass is both simpler and cheaper.
    """
    best: tuple | None = None
    best_distance = float("inf")
    for row in db.execute(REVERSE_SQL[table]):
        distance = meters_between(
            lat, lon, row[1] / COORD_SCALE, row[2] / COORD_SCALE
        )
        if distance < best_distance:
            best, best_distance = row, distance
    if best is None:
        return None, None
    return best, best_distance


def nearest(
    db: sqlite3.Connection, table: str, lat: float, lon: float
) -> tuple[tuple, float] | tuple[None, None]:
    """Nearest row in one table, growing the bounding box until something hits.

    Falls back to a single full scan when the table has no positional index.
    """
    if not has_position_index(db, table):
        return nearest_by_scan(db, table, lat, lon)
    for degrees in (0.02, 0.1, 0.5, 2.0):
        dlon = degrees / max(0.05, math.cos(math.radians(lat)))
        rows = db.execute(
            REVERSE_SQL[table]
            + " WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
            (
                int((lat - degrees) * COORD_SCALE),
                int((lat + degrees) * COORD_SCALE),
                int((lon - dlon) * COORD_SCALE),
                int((lon + dlon) * COORD_SCALE),
            ),
        ).fetchall()
        if not rows:
            continue
        best = min(
            rows,
            key=lambda r: meters_between(lat, lon, r[1] / COORD_SCALE, r[2] / COORD_SCALE),
        )
        return best, meters_between(
            lat, lon, best[1] / COORD_SCALE, best[2] / COORD_SCALE
        )
    return None, None


def parse_near(raw: str) -> tuple[float, float]:
    lat, _, lon = raw.partition(",")
    return float(lat), float(lon)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("db", help="a gazetteer tile, e.g. fixtures/E5_N45.gaz")
    parser.add_argument(
        "args", nargs="*", help="search text, or LAT LON for --reverse"
    )
    parser.add_argument("--reverse", action="store_true", help="reverse lookup")
    parser.add_argument("--near", default=None, help="map centre as LAT,LON")
    parser.add_argument(
        "--kind",
        default=None,
        help="with --near: list the nearest pois of this kind instead of searching",
    )
    parser.add_argument("--limit", type=int, default=10)
    options = parser.parse_args()

    db = sqlite3.connect(f"file:{options.db}?mode=ro", uri=True)

    if options.kind:
        if not options.near:
            parser.error("--kind needs --near LAT,LON")
        lat, lon = parse_near(options.near)
        started = time.perf_counter()
        rows = nearest_of_kind(db, options.kind, lat, lon, options.limit)
        elapsed = (time.perf_counter() - started) * 1000
        for _, name, row_lat, row_lon, place_id, distance in rows:
            context = place_name(db, place_id)
            label = name if name is not None else f"({options.kind})"
            print(
                f"{distance / 1000:>8.2f} km  {label:<40} "
                f"{row_lat:>9.5f},{row_lon:>10.5f}"
                f"{'  (' + context + ')' if context else ''}"
            )
        if not rows:
            print(f"(no {options.kind} within {KIND_RADII_KM[-1]:.0f} km)")
        print(f"({len(rows)} rows, {elapsed:.1f} ms)")
        return 0

    if not options.args:
        parser.error("nothing to search for")

    if options.reverse:
        if len(options.args) != 2:
            parser.error("--reverse needs LAT LON")
        lat, lon = float(options.args[0]), float(options.args[1])
        started = time.perf_counter()
        scanned = {table for table in REVERSE_SQL if not has_position_index(db, table)}
        found = {table: nearest(db, table, lat, lon) for table in REVERSE_SQL}
        elapsed = (time.perf_counter() - started) * 1000
        for table, (row, distance) in found.items():
            note = "  (scan)" if table in scanned else ""
            if row is None:
                print(f"{table:<8} -{note}")
                continue
            context = place_name(db, row[4])
            print(
                f"{table:<8} {row[0]}"
                f"{' (' + context + ')' if context else ''}"
                f"  [{row[3]}]  {distance:.0f} m  "
                f"{row[1] / COORD_SCALE:.5f},{row[2] / COORD_SCALE:.5f}{note}"
            )
        print(f"({elapsed:.1f} ms)")
        return 0

    text = " ".join(options.args)
    if len(text.strip()) < MIN_QUERY_CHARS:
        print(f"(the app does not query below {MIN_QUERY_CHARS} characters)")
    near = parse_near(options.near) if options.near else None
    started = time.perf_counter()
    rows = search(db, text, options.limit, near)
    elapsed = (time.perf_counter() - started) * 1000
    for hit in rows:
        extra = []
        if hit.context:
            extra.append(hit.context)
        if hit.population:
            extra.append(f"pop {hit.population}")
        if hit.distance_m is not None:
            extra.append(f"{hit.distance_m / 1000:.1f} km")
        suffix = f"  ({', '.join(extra)})" if extra else ""
        label = hit.name
        if hit.house_number is not None:
            mark = "≈ " if hit.approximate else ""
            label = f"{hit.name} {mark}{hit.house_number}"
        print(f"{hit.kind:<14} {label:<40} {hit.lat:>9.5f},{hit.lon:>10.5f}{suffix}")
    if not rows:
        print("(no matches)")
    print(f"({len(rows)} rows, {elapsed:.1f} ms)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
