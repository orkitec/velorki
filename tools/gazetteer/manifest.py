#!/usr/bin/env python3
"""Add the `gazetteer` object to the tile entries of a mirror manifest.

    manifest.py /segments4

Reads `<dir>/manifest.json` (the file `brouter/updater/sync.sh` writes) and,
for every tile entry, looks for `<dir>/<TILE>.gaz`:

  * present  -> validate it with check.py and set
                `"gazetteer": {"bytes", "sha256", "updatedAt"}`
  * absent   -> remove any `gazetteer` object left over from an earlier run

The manifest is written back with indent 1 and its key order untouched, so
running this twice over the same directory produces the same bytes. A .gaz
that fails check.py stops the run with a non-zero exit.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from check import GazetteerError, check  # noqa: E402


def sha256_of(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def updated_at(path: str) -> str:
    """The file's mtime, so a re-run of an unchanged mirror changes nothing."""
    stamp = datetime.fromtimestamp(os.path.getmtime(path), timezone.utc)
    return stamp.strftime("%Y-%m-%dT%H:%M:%SZ")


def gazetteer_entry(path: str) -> dict[str, Any]:
    check(path)  # raises GazetteerError
    return {
        "bytes": os.path.getsize(path),
        "sha256": sha256_of(path),
        "updatedAt": updated_at(path),
    }


def update_manifest(directory: str, verbose: bool = True) -> int:
    """Refresh every tile entry's gazetteer object. Returns how many have one."""
    manifest_path = os.path.join(directory, "manifest.json")
    with open(manifest_path, encoding="utf-8") as handle:
        manifest = json.load(handle)

    tiles = manifest.get("tiles")
    if not isinstance(tiles, list):
        raise GazetteerError(f"{manifest_path}: no tiles array")

    named = set()
    count = 0
    for entry in tiles:
        tile = entry.get("tile")
        if not tile:
            continue
        named.add(tile)
        path = os.path.join(directory, f"{tile}.gaz")
        if os.path.isfile(path):
            entry["gazetteer"] = gazetteer_entry(path)
            count += 1
            if verbose:
                print(f"{tile}: gazetteer {entry['gazetteer']['bytes']} bytes")
        elif entry.pop("gazetteer", None) is not None and verbose:
            print(f"{tile}: gazetteer removed, no {tile}.gaz")

    if verbose:
        for name in sorted(os.listdir(directory)):
            if name.endswith(".gaz") and name[: -len(".gaz")] not in named:
                print(f"warning: {name} has no tile entry in manifest.json")

    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1)
        handle.write("\n")
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", help="a mirror directory holding manifest.json")
    parser.add_argument("-q", "--quiet", action="store_true")
    args = parser.parse_args()

    try:
        count = update_manifest(args.directory, verbose=not args.quiet)
    except GazetteerError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    except (OSError, json.JSONDecodeError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    if not args.quiet:
        print(f"manifest.json updated ({count} tile(s) with a gazetteer)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
