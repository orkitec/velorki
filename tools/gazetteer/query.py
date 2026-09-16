#!/usr/bin/env python3
"""Run the app's gazetteer queries from the command line.

    query.py fixtures/E5_N45.gaz muhleholz
    query.py fixtures/E5_N45.gaz vad --near 47.141,9.521
    query.py --reverse fixtures/E5_N45.gaz 47.1410 9.5215

The forward form is exactly what the app runs: one FTS statement, then three
primary-key lookups per hit, then the ranking in Python (bm25, name length, population,
distance to `--near`). The reverse form is the nearest street, place and POI
to a coordinate, found with a bounding box on the lat/lon indexes.
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
    name: str
    kind: str
    lat: float
    lon: float
    population: int | None
    context: str | None
    rank: float
    distance_m: float | None


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


def search(
    db: sqlite3.Connection,
    text: str,
    limit: int,
    near: tuple[float, float] | None = None,
) -> list[Hit]:
    hits: list[Hit] = []
    for rowid, rank in db.execute(SEARCH_SQL, (fts_query(text),)):
        for statement in HYDRATE.values():
            row = db.execute(statement, (rowid,)).fetchone()
            if row is None:
                continue
            name, kind, lat, lon, population, ref = row
            lat, lon = lat / COORD_SCALE, lon / COORD_SCALE
            distance = (
                meters_between(near[0], near[1], lat, lon) if near is not None else None
            )
            hits.append(
                Hit(name, kind, lat, lon, population, place_name(db, ref), rank, distance)
            )
            break

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


# The reverse lookup asks the same four columns of each table; only the kind
# and the foreign key are named differently.
REVERSE_SQL = {
    "streets": "SELECT name, lat, lon, 'street', place_id FROM streets",
    "places": "SELECT name, lat, lon, kind, admin_id FROM places",
    "pois": "SELECT name, lat, lon, kind, place_id FROM pois",
}


def nearest(
    db: sqlite3.Connection, table: str, lat: float, lon: float
) -> tuple[tuple, float] | tuple[None, None]:
    """Nearest row in one table, growing the bounding box until something hits."""
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
    parser.add_argument("args", nargs="+", help="search text, or LAT LON for --reverse")
    parser.add_argument("--reverse", action="store_true", help="reverse lookup")
    parser.add_argument("--near", default=None, help="map centre as LAT,LON")
    parser.add_argument("--limit", type=int, default=10)
    options = parser.parse_args()

    db = sqlite3.connect(f"file:{options.db}?mode=ro", uri=True)

    if options.reverse:
        if len(options.args) != 2:
            parser.error("--reverse needs LAT LON")
        lat, lon = float(options.args[0]), float(options.args[1])
        started = time.perf_counter()
        found = {table: nearest(db, table, lat, lon) for table in REVERSE_SQL}
        elapsed = (time.perf_counter() - started) * 1000
        for table, (row, distance) in found.items():
            if row is None:
                print(f"{table:<8} -")
                continue
            context = place_name(db, row[4])
            print(
                f"{table:<8} {row[0]}"
                f"{' (' + context + ')' if context else ''}"
                f"  [{row[3]}]  {distance:.0f} m  "
                f"{row[1] / COORD_SCALE:.5f},{row[2] / COORD_SCALE:.5f}"
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
        print(f"{hit.kind:<14} {hit.name:<40} {hit.lat:>9.5f},{hit.lon:>10.5f}{suffix}")
    if not rows:
        print("(no matches)")
    print(f"({len(rows)} rows, {elapsed:.1f} ms)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
