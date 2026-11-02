#!/usr/bin/env python3
"""The content digest of a `<TILE>.gaz`: what the file says, not when it was made.

    digest.py fixtures/E5_N45.gaz

A rebuild of unchanged data differs from the last file only in `built_at`,
yet its sha256 differs entirely, so a mirror that publishes every month would
have every phone fetch every file again. This digest leaves `built_at` out
and reads the rows rather than the pages, so it changes when, and only when,
what a search can find changes; SQLite's page layout does not come into it.

The app computes the same digest (`gazetteer_digest.dart`) for files it
already has, so both must follow this definition exactly:

  sha256 over, for every table in `sqlite_master` (type 'table', not virtual,
  name not starting `sqlite_`), in ascending order of name:
    the tag byte 0x54, the name as a value (below), then for every row of
    `SELECT * FROM "<name>" ORDER BY 1, 2, ..., n` (all its columns, in SQLite's
    own order) the tag byte 0x52 and each column as a value;
  the row of `meta` whose key is `built_at` is skipped.

  A value: NULL 0x00; INTEGER 0x01 + 8 bytes, signed big-endian; REAL 0x02 +
  8 bytes, IEEE 754 big-endian; TEXT 0x03 + 4-byte big-endian length + UTF-8;
  BLOB 0x04 + 4-byte big-endian length + bytes.

The FTS5 index's own tables (`search_data`, `search_idx`, ...) are ordinary
tables and count: a change in how names are transliterated changes what a
search finds while every row of `places` stays the same.
"""

from __future__ import annotations

import argparse
import hashlib
import sqlite3
import struct
import sys

_TABLE = b"T"
_ROW = b"R"


def _value(value: object) -> bytes:
    if value is None:
        return b"\x00"
    if isinstance(value, bool):  # never from SQLite, but an int subclass
        value = int(value)
    if isinstance(value, int):
        return b"\x01" + struct.pack(">q", value)
    if isinstance(value, float):
        return b"\x02" + struct.pack(">d", value)
    if isinstance(value, str):
        data = value.encode("utf-8")
        return b"\x03" + struct.pack(">I", len(data)) + data
    if isinstance(value, (bytes, bytearray, memoryview)):
        data = bytes(value)
        return b"\x04" + struct.pack(">I", len(data)) + data
    raise TypeError(f"unexpected SQLite value {type(value).__name__}")


def gazetteer_digest(path: str) -> str:
    """The content digest of the `.gaz` at [path], as lower-case hex."""
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        tables = sorted(
            row[0]
            for row in db.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
                " AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'"
                " AND sql NOT LIKE 'CREATE VIRTUAL TABLE%'"
            )
        )
        digest = hashlib.sha256()
        for table in tables:
            digest.update(_TABLE + _value(table))
            quoted = '"' + table.replace('"', '""') + '"'
            columns = len(db.execute(f"SELECT * FROM {quoted} LIMIT 0").description)
            order = ", ".join(str(i) for i in range(1, columns + 1))
            for row in db.execute(f"SELECT * FROM {quoted} ORDER BY {order}"):
                if table == "meta" and row[0] == "built_at":
                    continue
                digest.update(_ROW)
                for value in row:
                    digest.update(_value(value))
        return digest.hexdigest()
    finally:
        db.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", help=".gaz files")
    args = parser.parse_args()
    for path in args.paths:
        print(f"{gazetteer_digest(path)}  {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
