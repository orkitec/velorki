#!/usr/bin/env python3
"""Merge partial `<TILE>.gaz` files into one complete file per tile.

    merge.py out gaz/liechtenstein gaz/switzerland gaz/austria

Geofabrik extracts overlap at their edges and none of them covers a whole
5 degree tile, so a tile is built once per extract that touches it and the
partial files are merged here. Input directories are searched recursively, so
one directory per extract (or the flat download of a CI matrix) both work.

Rows are deduplicated by their OSM identity — (`osm_type`, `osm_id`) for a
place, (`osm_type`, `osm_id`, `kind`) for a POI, because one object may be both
a `toilets` row and a `drinking_water` row. Streets have no identity: a street row is the mean of many ways, so two
extracts that both cover it produce two slightly different rows, and those are
matched by name, the place they hang off and their position rounded to
1e-3 degrees (about 100 m). Ids are then handed out from a single counter
across the three tables, exactly as build.py does, and `admin_id` / `place_id`
are remapped onto the surviving rows.

A tile that only one input holds goes through the same path, so the output is
always canonical.

Standard library only: the merge job in CI must not need pyosmium.
"""

from __future__ import annotations

import argparse
import os
import sqlite3
import sys
from datetime import datetime, timezone
from typing import Any, NamedTuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from check import GazetteerError, check  # noqa: E402

SCHEMA_VERSION = "1"

# Streets are matched on their position rounded to this many degrees, because
# two extracts see different parts of the same street and put its centre in
# slightly different places.
STREET_ROUND_DEG = 1e-3

COORD_SCALE = 1e7

# Kept byte-for-byte in step with build.py's SCHEMA; the tests assert that a
# merged file and a built file declare exactly the same tables and indexes.
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
    name     TEXT,
    kind     TEXT NOT NULL,
    lat      INTEGER NOT NULL,
    lon      INTEGER NOT NULL,
    place_id INTEGER,
    osm_type TEXT,
    osm_id   INTEGER
);

CREATE TABLE aliases (
    id     INTEGER PRIMARY KEY,
    ref_id INTEGER NOT NULL,
    name   TEXT NOT NULL
);

CREATE TABLE house_numbers (
    street_id INTEGER NOT NULL,
    number    INTEGER NOT NULL,
    lat       INTEGER NOT NULL,
    lon       INTEGER NOT NULL,
    PRIMARY KEY (street_id, number)
) WITHOUT ROWID;

CREATE VIRTUAL TABLE search USING fts5(
    name,
    content='',
    columnsize=0,
    tokenize='unicode61 remove_diacritics 2'
);

CREATE INDEX idx_places_pos  ON places(lat, lon);
CREATE INDEX idx_streets_pos ON streets(lat, lon);
CREATE INDEX idx_pois_pos    ON pois(lat, lon);
CREATE INDEX idx_aliases_ref ON aliases(ref_id);
"""

# The anchor cap build.py applies. A merged street holds the union of its
# inputs' anchors, which is thinned again to stay under it.
MAX_ANCHORS = 40

# The columns every version 1 file has, in order. osm_type and osm_id are read
# separately because files built before the addendum do not have them.
BASE_COLUMNS = {
    "places": ("id", "name", "kind", "lat", "lon", "population", "admin_id"),
    "streets": ("id", "name", "lat", "lon", "place_id"),
    "pois": ("id", "name", "kind", "lat", "lon", "place_id"),
}

# Which column of each table points at places.id.
REFERENCE = {"places": "admin_id", "streets": "place_id", "pois": "place_id"}

TABLES = ("places", "streets", "pois")


class Row(NamedTuple):
    """One input row, still carrying the id and reference of its own file."""

    table: str
    values: tuple  # BASE_COLUMNS[table] order, id first
    osm_type: str | None
    osm_id: int | None
    source_index: int  # which input file it came from

    @property
    def id(self) -> int:
        return self.values[0]

    @property
    def name(self) -> str:
        return self.values[1]


# --------------------------------------------------------------------------
# reading
# --------------------------------------------------------------------------


def find_inputs(directories: list[str]) -> list[str]:
    """Every `*.gaz` under the given directories, in a stable order.

    A directory may be given directly instead; a file path is taken as is, so
    `merge.py out a/E5_N45.gaz b/E5_N45.gaz` works too.
    """
    found: list[str] = []
    seen: set[str] = set()
    for directory in directories:
        if os.path.isfile(directory):
            candidates = [directory]
        else:
            candidates = []
            for root, dirs, files in os.walk(directory):
                dirs.sort()
                candidates += [
                    os.path.join(root, name)
                    for name in sorted(files)
                    if name.endswith(".gaz")
                ]
        for path in candidates:
            real = os.path.realpath(path)
            if real in seen:
                continue
            seen.add(real)
            found.append(path)
    return found


def has_osm_columns(db: sqlite3.Connection, table: str) -> bool:
    columns = {row[1] for row in db.execute(f"PRAGMA table_info({table})")}
    return "osm_type" in columns and "osm_id" in columns


def has_table(db: sqlite3.Connection, table: str) -> bool:
    return (
        db.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (table,)
        ).fetchone()
        is not None
    )


class Input(NamedTuple):
    """One input file: its rows, its aliases and its house numbers."""

    rows: dict[str, list[Row]]
    aliases: list[tuple[int, str]]  # (ref_id, name), in id order
    numbers: list[tuple[int, int, int, int]]  # (street_id, number, lat, lon)


def read_file(path: str, index: int) -> tuple[dict[str, Any], Input]:
    """The meta dict and everything in one input file.

    `aliases` and `house_numbers` are optional: a file built before they
    existed simply contributes none.
    """
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        meta = dict(db.execute("SELECT key, value FROM meta"))
        rows: dict[str, list[Row]] = {}
        for table in TABLES:
            base = BASE_COLUMNS[table]
            osm = has_osm_columns(db, table)
            columns = ", ".join(base + (("osm_type", "osm_id") if osm else ()))
            rows[table] = [
                Row(
                    table,
                    tuple(record[: len(base)]),
                    record[len(base)] if osm else None,
                    record[len(base) + 1] if osm else None,
                    index,
                )
                for record in db.execute(f"SELECT {columns} FROM {table} ORDER BY id")
            ]
        aliases = (
            [
                (record[0], record[1])
                for record in db.execute("SELECT ref_id, name FROM aliases ORDER BY id")
            ]
            if has_table(db, "aliases")
            else []
        )
        numbers = (
            [
                tuple(record)
                for record in db.execute(
                    "SELECT street_id, number, lat, lon FROM house_numbers"
                    " ORDER BY street_id, number"
                )
            ]
            if has_table(db, "house_numbers")
            else []
        )
    finally:
        db.close()
    return meta, Input(rows, aliases, numbers)


# --------------------------------------------------------------------------
# deduplication
# --------------------------------------------------------------------------


def rounded(coordinate: int) -> int:
    """A 1e-7 degree integer rounded to the 1e-3 degree street grid."""
    return int(round(coordinate / (COORD_SCALE * STREET_ROUND_DEG)))


def dedup_key(row: Row, place_name: str | None) -> tuple | None:
    """What makes two rows the same row, or None when they cannot be matched.

    OSM identity wins wherever a row has one, and for a POI the kind is part of
    it: one object may be a `toilets` row and a `drinking_water` row, and those
    two must survive a merge as two rows. A street has no identity at all, so
    it falls back to its name, the place it belongs to and its rounded
    position. A place or POI out of a file built before the addendum has
    neither, and is kept as it is: dropping it would lose data, keeping it can
    only duplicate.
    """
    if row.osm_type is not None and row.osm_id is not None:
        if row.table == "pois":
            return ("pois", "osm", row.osm_type, row.osm_id, row.values[2])
        return (row.table, "osm", row.osm_type, row.osm_id)
    if row.table == "streets":
        return (
            "streets",
            "pos",
            row.name,
            place_name,
            rounded(row.values[2]),
            rounded(row.values[3]),
        )
    return None


def thin_anchors(entries: list[tuple[int, int, int]]) -> list[tuple[int, int, int]]:
    """The union of two inputs' anchors, back under MAX_ANCHORS.

    What comes in here is already thinned — build.py's "every tenth" ran over
    the addresses, which merge.py never sees — so running that step again would
    throw away nine anchors in ten every time a file passed through a merge, and
    merging a file with a copy of itself would not be a no-op. Only the cap is
    re-applied: the lowest and the highest number always survive, and the rest
    are sampled evenly.
    """
    if len(entries) <= MAX_ANCHORS:
        return entries
    inner = entries[1:-1]
    keep = MAX_ANCHORS - 2
    return (
        [entries[0]]
        + [inner[(index * len(inner)) // keep] for index in range(keep)]
        + [entries[-1]]
    )


class Merged(NamedTuple):
    rows: dict[str, list[tuple]]  # table -> final rows, ids and refs remapped
    aliases: list[tuple[int, int, str]]  # (id, ref_id, name)
    numbers: list[tuple[int, int, int, int]]
    rows_in: int
    rows_out: int


def merge_rows(files: list[Input]) -> Merged:
    """Deduplicate, renumber from one counter and remap the references."""
    # places.id -> name, per input file, for the street fallback key.
    place_names = [
        {row.id: row.name for row in per_file.rows["places"]} for per_file in files
    ]

    # (file index, old id) -> new id of whichever row survived.
    remap: dict[tuple[int, int], int] = {}
    winners: dict[tuple, int] = {}  # dedup key -> new id
    kept: dict[str, list[Row]] = {table: [] for table in TABLES}

    next_id = 1
    rows_in = 0
    # places first, then streets, then pois: build.py hands out ids in that
    # order and a merged file should be indistinguishable from a built one.
    for table in TABLES:
        for per_file in files:
            for row in per_file.rows[table]:
                rows_in += 1
                place_id = row.values[BASE_COLUMNS[table].index(REFERENCE[table])]
                key = dedup_key(
                    row,
                    place_names[row.source_index].get(place_id)
                    if table == "streets"
                    else None,
                )
                if key is not None and key in winners:
                    # A dropped duplicate hands its references to its survivor.
                    remap[(row.source_index, row.id)] = winners[key]
                    continue
                remap[(row.source_index, row.id)] = next_id
                if key is not None:
                    winners[key] = next_id
                kept[table].append(row._replace(values=(next_id,) + row.values[1:]))
                next_id += 1

    out: dict[str, list[tuple]] = {}
    for table in TABLES:
        reference_index = BASE_COLUMNS[table].index(REFERENCE[table])
        final: list[tuple] = []
        for row in kept[table]:
            values = list(row.values)
            old = values[reference_index]
            values[reference_index] = (
                remap.get((row.source_index, old)) if old is not None else None
            )
            final.append(tuple(values) + (row.osm_type, row.osm_id))
        out[table] = final

    # Aliases come after the three tables, exactly as build.py hands them out.
    # A name that two extracts both saw on the same object is one row.
    aliases: list[tuple[int, int, str]] = []
    seen_aliases: set[tuple[int, str]] = set()
    for index, per_file in enumerate(files):
        for ref_id, name in per_file.aliases:
            new_ref = remap.get((index, ref_id))
            if new_ref is None:
                continue  # its row did not survive; nothing left to point at
            key = (new_ref, name)
            if key in seen_aliases:
                continue
            seen_aliases.add(key)
            aliases.append((next_id, new_ref, name))
            next_id += 1
            rows_in += 1

    # Two extracts see different stretches of the same street, so their anchors
    # are the union and the thinning runs again over it.
    per_street: dict[int, dict[int, tuple[int, int]]] = {}
    for index, per_file in enumerate(files):
        for street_id, number, lat, lon in per_file.numbers:
            new_street = remap.get((index, street_id))
            if new_street is None:
                continue
            per_street.setdefault(new_street, {}).setdefault(number, (lat, lon))
    numbers: list[tuple[int, int, int, int]] = []
    for street_id in sorted(per_street):
        bucket = per_street[street_id]
        entries = [(number,) + bucket[number] for number in sorted(bucket)]
        numbers += [
            (street_id, number, lat, lon) for number, lat, lon in thin_anchors(entries)
        ]

    return Merged(out, aliases, numbers, rows_in, next_id - 1)


# --------------------------------------------------------------------------
# writing
# --------------------------------------------------------------------------


def write_tile(path: str, tile: str, merged: Merged, meta: list[tuple[str, str]]) -> int:
    if os.path.exists(path):
        os.remove(path)
    db = sqlite3.connect(path)
    db.executescript(
        "PRAGMA page_size=4096;"
        "PRAGMA journal_mode=DELETE;"
        "PRAGMA synchronous=OFF;"
    )
    db.executescript(SCHEMA)

    for table in TABLES:
        columns = BASE_COLUMNS[table] + ("osm_type", "osm_id")
        placeholders = ",".join("?" * len(columns))
        db.executemany(
            f"INSERT INTO {table} ({', '.join(columns)}) VALUES ({placeholders})",
            merged.rows[table],
        )
    db.executemany(
        "INSERT INTO aliases (id, ref_id, name) VALUES (?,?,?)", merged.aliases
    )
    db.executemany(
        "INSERT INTO house_numbers (street_id, number, lat, lon) VALUES (?,?,?,?)",
        merged.numbers,
    )
    # An unnamed utility row has nothing to match, so it stays out of the index.
    db.executemany(
        "INSERT INTO search(rowid, name) VALUES (?,?)",
        [
            (row[0], row[1])
            for table in TABLES
            for row in merged.rows[table]
            if row[1] is not None
        ]
        + [(row[0], row[2]) for row in merged.aliases],
    )
    db.executemany("INSERT INTO meta VALUES (?,?)", meta)
    db.commit()
    db.execute("INSERT INTO search(search) VALUES ('optimize')")
    db.commit()
    db.execute("VACUUM")
    db.close()
    return os.path.getsize(path)


def meta_rows(tile: str, metas: list[dict[str, Any]], built_at: str) -> list[tuple[str, str]]:
    sources: list[str] = []
    for meta in metas:
        source = meta.get("source") or ""
        if source and source not in sources:
            sources.append(source)
    return [
        ("schema_version", SCHEMA_VERSION),
        ("tile", tile),
        ("built_at", built_at),
        ("source", ",".join(sources)),
        ("has_streets", "1" if any(m.get("has_streets") == "1" for m in metas) else "0"),
        ("has_pois", "1" if any(m.get("has_pois") == "1" for m in metas) else "0"),
    ]


class TileResult(NamedTuple):
    tile: str
    inputs: int
    rows_in: int
    rows_out: int
    bytes: int


def merge_tile(out_dir: str, tile: str, paths: list[str], built_at: str) -> TileResult:
    metas: list[dict[str, Any]] = []
    files: list[Input] = []
    for index, path in enumerate(paths):
        meta, contents = read_file(path, index)
        metas.append(meta)
        files.append(contents)
    merged = merge_rows(files)
    size = write_tile(
        os.path.join(out_dir, f"{tile}.gaz"),
        tile,
        merged,
        meta_rows(tile, metas, built_at),
    )
    return TileResult(tile, len(paths), merged.rows_in, merged.rows_out, size)


def group_by_tile(paths: list[str]) -> dict[str, list[str]]:
    tiles: dict[str, list[str]] = {}
    for path in paths:
        tile = os.path.basename(path)[: -len(".gaz")]
        tiles.setdefault(tile, []).append(path)
    return tiles


def merge(out_dir: str, in_dirs: list[str], verbose: bool = True) -> list[TileResult]:
    """Merge every tile found under `in_dirs` into `out_dir`.

    Raises GazetteerError when an input does not pass check.py; nothing is
    written in that case.
    """
    inputs = find_inputs(in_dirs)
    if not inputs:
        raise GazetteerError(f"no .gaz files under {', '.join(in_dirs)}")
    # Validate everything first: a half-written output directory is worse than
    # no output at all.
    for path in inputs:
        check(path)

    os.makedirs(out_dir, exist_ok=True)
    built_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    results = []
    for tile, paths in sorted(group_by_tile(inputs).items()):
        result = merge_tile(out_dir, tile, paths, built_at)
        results.append(result)
        if verbose:
            print(
                f"{result.tile:<12} {result.inputs:>2} input(s)  "
                f"{result.rows_in:>8} -> {result.rows_out:>8} rows  "
                f"{result.bytes / 1e6:>8.2f}M"
            )
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("out_dir", help="directory the merged tiles are written to")
    parser.add_argument(
        "in_dirs", nargs="+", help="directories holding <TILE>.gaz files (searched recursively)"
    )
    parser.add_argument("-q", "--quiet", action="store_true")
    args = parser.parse_args()

    try:
        results = merge(args.out_dir, args.in_dirs, verbose=not args.quiet)
    except GazetteerError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    except (OSError, sqlite3.Error) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    if not args.quiet:
        total = sum(r.bytes for r in results)
        print(f"{len(results)} tile(s), {total / 1e6:.2f}M in {args.out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
