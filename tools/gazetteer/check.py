#!/usr/bin/env python3
"""Validate a `<TILE>.gaz` file and print a one-line summary.

    check.py fixtures/E5_N45.gaz

Checks the schema version, that `meta.tile` matches the file name, that the
FTS index actually answers a query, and reports the row counts. The optional
`osm_type`/`osm_id` columns are accepted whether or not a file has them. Used by
manifest.py before it writes a gazetteer entry, and by the tests.
"""

from __future__ import annotations

import argparse
import os
import sqlite3
from typing import NamedTuple

SCHEMA_VERSION = "1"

TABLES = ("meta", "places", "streets", "pois", "search")


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

    def summary(self) -> str:
        kinds = ["places", "pois"] if self.has_pois else ["places"]
        if self.has_streets:
            kinds.insert(1, "streets")
        return (
            f"{os.path.basename(self.path)}  {self.tile}  "
            f"{self.places} places, {self.streets} streets, {self.pois} pois, "
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
        # the row count of the three tables; that every row really made it in
        # is what _check_query proves.
        counts = {
            table: db.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
            for table in ("places", "streets", "pois")
        }
        counts["search"] = counts["places"] + counts["streets"] + counts["pois"]
        if counts["search"] == 0:
            raise GazetteerError(f"{path}: holds no rows at all")

        _check_osm_columns(db, path)
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
    )


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


def _check_query(db: sqlite3.Connection, path: str) -> None:
    """Take a real name out of the tables and prove the FTS index finds it."""
    for table in ("places", "pois", "streets"):
        row = db.execute(f"SELECT id, name FROM {table} LIMIT 1").fetchone()
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
