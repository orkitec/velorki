#!/usr/bin/env python3
"""Validate a `<TILE>.gaz` file and print a one-line summary.

    check.py fixtures/E5_N45.gaz

Checks the schema version, that `meta.tile` matches the file name, that the
FTS index actually answers a query, and reports the row counts. A POI may have
a NULL name only when its kind is one of the unnamed utility kinds, and an
unnamed row must not be in the FTS index, so the indexed count is the named
rows plus the aliases. No two POI rows share an (osm_type, osm_id, kind). The
optional `osm_type`/`osm_id` columns and the optional `aliases` /
`house_numbers` tables are accepted whether or not a file has them; when a file
does have them, every `ref_id` and `street_id` must resolve and no street may
carry more than 40 anchors. Used by manifest.py before it writes a gazetteer
entry, and by the tests.
"""

from __future__ import annotations

import argparse
import os
import sqlite3
from typing import NamedTuple

SCHEMA_VERSION = "1"

TABLES = ("meta", "places", "streets", "pois", "search")

# Must match build.py's MAX_ANCHORS.
MAX_ANCHORS = 40

# Must match build.py's UNNAMED_KINDS: the only kinds a POI may carry with no
# name, because the app finds them by position rather than by typing.
UNNAMED_KINDS = frozenset(
    """
    drinking_water toilets bicycle_repair_station shelter bicycle_rental
    charging_station picnic_site bicycle_parking
    """.split()
)


class GazetteerError(Exception):
    """A .gaz file that is not a valid version 1 gazetteer."""


class Report(NamedTuple):
    path: str
    tile: str
    built_at: str
    source: str
    has_streets: bool
    has_pois: bool
    places: int
    streets: int
    pois: int
    search: int
    bytes: int
    aliases: int = 0
    house_numbers: int = 0
    unnamed_pois: int = 0

    def summary(self) -> str:
        kinds = ["places", "pois"] if self.has_pois else ["places"]
        if self.has_streets:
            kinds.insert(1, "streets")
        return (
            f"{os.path.basename(self.path)}  {self.tile}  "
            f"{self.places} places, {self.streets} streets, "
            f"{self.pois} pois ({self.unnamed_pois} unnamed), "
            f"{self.aliases} aliases, {self.house_numbers} house numbers, "
            f"{self.search} indexed  {self.bytes / 1e6:.2f} MB  "
            f"[{'+'.join(kinds)}]  built {self.built_at}  from {self.source}"
        )


def check(path: str) -> Report:
    """Validate one gazetteer file, or raise GazetteerError."""
    if not os.path.isfile(path):
        raise GazetteerError(f"{path}: not a file")
    name = os.path.basename(path)
    if not name.endswith(".gaz"):
        raise GazetteerError(f"{path}: expected a .gaz file name")
    expected_tile = name[: -len(".gaz")]

    try:
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    except sqlite3.Error as error:
        raise GazetteerError(f"{path}: cannot open ({error})") from error

    try:
        present = {
            row[0]
            for row in db.execute(
                "SELECT name FROM sqlite_master WHERE type IN ('table','view')"
            )
        }
        missing = [t for t in TABLES if t not in present]
        if missing:
            raise GazetteerError(f"{path}: missing table(s) {', '.join(missing)}")

        try:
            meta = dict(db.execute("SELECT key, value FROM meta"))
        except sqlite3.Error as error:
            raise GazetteerError(f"{path}: meta is not a key/value table ({error})")

        version = meta.get("schema_version")
        if version != SCHEMA_VERSION:
            raise GazetteerError(
                f"{path}: schema_version is {version!r}, expected {SCHEMA_VERSION!r}"
            )
        tile = meta.get("tile")
        if tile != expected_tile:
            raise GazetteerError(
                f"{path}: meta.tile is {tile!r}, expected {expected_tile!r}"
            )

        # A contentless FTS5 table cannot be scanned, so the indexed count is
        # worked out from the tables: every named row plus every alias. That
        # the named rows really made it in is what _check_query proves, and
        # that no unnamed one did is _check_unnamed_are_not_indexed.
        counts = {
            table: db.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
            for table in ("places", "streets", "pois")
        }
        if counts["places"] + counts["streets"] + counts["pois"] == 0:
            raise GazetteerError(f"{path}: holds no rows at all")

        counts["unnamed_pois"] = _check_names(db, path)
        # An unnamed row has nothing to match, so it is not in the index.
        counts["search"] = (
            counts["places"] + counts["streets"] + counts["pois"]
            - counts["unnamed_pois"]
        )

        _check_osm_columns(db, path)
        extra = _check_extra_tables(db, path)
        counts["search"] += extra["aliases"]
        counts.update(extra)
        _check_unnamed_are_not_indexed(db, path)
        _check_query(db, path)
    finally:
        db.close()

    return Report(
        path=path,
        tile=tile,
        built_at=meta.get("built_at", ""),
        source=meta.get("source", ""),
        has_streets=meta.get("has_streets") == "1",
        has_pois=meta.get("has_pois") == "1",
        places=counts["places"],
        streets=counts["streets"],
        pois=counts["pois"],
        search=counts["search"],
        bytes=os.path.getsize(path),
        aliases=counts["aliases"],
        house_numbers=counts["house_numbers"],
        unnamed_pois=counts["unnamed_pois"],
    )


def _check_names(db: sqlite3.Connection, path: str) -> int:
    """Every row has a name, except a POI of an unnamed utility kind.

    Returns how many POI rows have none; that is exactly the number of rows
    that must be missing from the FTS index.
    """
    for table in ("places", "streets"):
        blank = db.execute(
            f"SELECT count(*) FROM {table} WHERE name IS NULL OR name = ''"
        ).fetchone()[0]
        if blank:
            raise GazetteerError(f"{path}: {blank} {table} row(s) without a name")

    bad = db.execute(
        "SELECT kind, count(*) FROM pois WHERE name IS NULL OR name = '' "
        "GROUP BY kind ORDER BY kind"
    ).fetchall()
    unnamed = 0
    for kind, count in bad:
        if kind not in UNNAMED_KINDS:
            raise GazetteerError(
                f"{path}: {count} unnamed poi row(s) of kind {kind!r}, "
                "which is not an unnamed utility kind"
            )
        unnamed += count
    return unnamed


def _check_osm_columns(db: sqlite3.Connection, path: str) -> None:
    """`osm_type`/`osm_id` are optional; when a table has them they must hold
    a real OSM type. Files built before the addendum have neither column and
    are valid as they are."""
    for table in ("places", "streets", "pois"):
        columns = {row[1] for row in db.execute(f"PRAGMA table_info({table})")}
        if not {"osm_type", "osm_id"} <= columns:
            continue
        bad = db.execute(
            f"SELECT osm_type FROM {table} "
            "WHERE osm_type IS NOT NULL AND osm_type NOT IN ('n','w','r') LIMIT 1"
        ).fetchone()
        if bad is not None:
            raise GazetteerError(f"{path}: {table}.osm_type is {bad[0]!r}")
        if table == "streets":
            continue  # a street is merged out of many ways and has no identity
        # The dedupe key: one row per OSM object per kind. A toilet with a tap
        # is a `toilets` row and a `drinking_water` row, and no more than that.
        key = "osm_type, osm_id" + (", kind" if table == "pois" else "")
        duplicate = db.execute(
            f"SELECT {key} FROM {table} WHERE osm_id IS NOT NULL "
            f"GROUP BY {key} HAVING count(*) > 1 LIMIT 1"
        ).fetchone()
        if duplicate is not None:
            raise GazetteerError(
                f"{path}: {table} holds {tuple(duplicate)} more than once"
            )


def _has_table(db: sqlite3.Connection, table: str) -> bool:
    return (
        db.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (table,)
        ).fetchone()
        is not None
    )


def _check_extra_tables(db: sqlite3.Connection, path: str) -> dict[str, int]:
    """`aliases` and `house_numbers` are optional, but not optionally correct.

    An alias has to point at a real row of one of the three tables, an anchor at
    a real street, and no street may carry more than MAX_ANCHORS anchors.
    """
    counts = {"aliases": 0, "house_numbers": 0}

    if _has_table(db, "aliases"):
        counts["aliases"] = db.execute("SELECT count(*) FROM aliases").fetchone()[0]
        dangling = db.execute(
            "SELECT ref_id FROM aliases WHERE ref_id NOT IN "
            "(SELECT id FROM places UNION ALL SELECT id FROM streets "
            " UNION ALL SELECT id FROM pois) LIMIT 1"
        ).fetchone()
        if dangling is not None:
            raise GazetteerError(
                f"{path}: aliases.ref_id {dangling[0]} is not a place, street or poi"
            )

    if _has_table(db, "house_numbers"):
        counts["house_numbers"] = db.execute(
            "SELECT count(*) FROM house_numbers"
        ).fetchone()[0]
        dangling = db.execute(
            "SELECT street_id FROM house_numbers "
            "WHERE street_id NOT IN (SELECT id FROM streets) LIMIT 1"
        ).fetchone()
        if dangling is not None:
            raise GazetteerError(
                f"{path}: house_numbers.street_id {dangling[0]} is not a street"
            )
        crowded = db.execute(
            "SELECT street_id, count(*) FROM house_numbers GROUP BY street_id "
            "HAVING count(*) > ? LIMIT 1",
            (MAX_ANCHORS,),
        ).fetchone()
        if crowded is not None:
            raise GazetteerError(
                f"{path}: street {crowded[0]} holds {crowded[1]} anchors, "
                f"more than {MAX_ANCHORS}"
            )

    return counts


def _check_unnamed_are_not_indexed(db: sqlite3.Connection, path: str) -> None:
    """An unnamed row has nothing to match, so it is not in the FTS index.

    A contentless FTS5 table cannot be scanned, so its documents are reached
    through an `fts5vocab` instance table and intersected with the unnamed
    rows inside SQLite: a dense tile has millions of documents and none of
    them needs to become a Python object.
    """
    try:
        db.execute(
            "CREATE VIRTUAL TABLE temp.gaz_index USING fts5vocab(main,'search','instance')"
        )
    except sqlite3.Error:
        return  # an SQLite too old for fts5vocab
    try:
        indexed = db.execute(
            "SELECT count(*) FROM (SELECT DISTINCT doc FROM temp.gaz_index)"
            " WHERE doc IN (SELECT id FROM pois WHERE name IS NULL)"
        ).fetchone()[0]
        if indexed:
            raise GazetteerError(
                f"{path}: {indexed} unnamed poi row(s) are in the FTS index"
            )
    finally:
        db.execute("DROP TABLE temp.gaz_index")


def _check_query(db: sqlite3.Connection, path: str) -> None:
    """Take a real name out of the tables and prove the FTS index finds it."""
    for table in ("places", "pois", "streets"):
        row = db.execute(
            f"SELECT id, name FROM {table} WHERE name IS NOT NULL LIMIT 1"
        ).fetchone()
        if row is None:
            continue
        rowid, name = row
        token = name.split()[0].replace('"', '""')
        try:
            hits = db.execute(
                "SELECT rowid FROM search WHERE search MATCH ? "
                "ORDER BY rank LIMIT 500",
                (f'"{token}"*',),
            ).fetchall()
        except sqlite3.Error as error:
            raise GazetteerError(f"{path}: the FTS index does not answer ({error})")
        if rowid not in {h[0] for h in hits}:
            raise GazetteerError(
                f"{path}: searching {name!r} does not return its own {table} row"
            )
        return


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", help="one or more <TILE>.gaz files")
    args = parser.parse_args()

    failed = False
    for path in args.files:
        try:
            print(check(path).summary())
        except GazetteerError as error:
            print(f"FAIL {error}")
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
