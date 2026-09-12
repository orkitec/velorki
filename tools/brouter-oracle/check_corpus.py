#!/usr/bin/env python3
"""Replay the recorded corpus and compare against corpus/index.json.

Comparison is exact: HTTP status, track-length, filtered ascend, plain-ascend,
cost, coordinate count, message count and the sha256 of the whole response body
must all be identical to what was recorded.

Exit code 0 when everything matches, 1 on any mismatch.

Usage: python3 check_corpus.py [--out <diff-file>] [--bodies]
  --out     where to write the machine-readable diff (default .cache/check-diff.txt)
  --bodies  also write the differing response bodies to .cache/check-bodies/
"""

from __future__ import annotations

import argparse
import os
import sys

from oracle_common import (
    INDEX_JSON,
    ORACLE_DIR,
    derive,
    http_get,
    load_json,
    sha256_hex,
    wait_for_server,
)

FIELDS = ["status", "track_length", "filtered_ascend", "plain_ascend",
          "cost", "coordinates", "messages", "sha256"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ORACLE_DIR, ".cache", "check-diff.txt"))
    ap.add_argument("--bodies", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(INDEX_JSON):
        print("no corpus/index.json -- run run_corpus.py first", file=sys.stderr)
        return 1

    wait_for_server()
    index = load_json(INDEX_JSON)
    cases = index["cases"]

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    bodies_dir = os.path.join(ORACLE_DIR, ".cache", "check-bodies")
    if args.bodies:
        os.makedirs(bodies_dir, exist_ok=True)

    lines = []
    mismatched = []
    per_field = {f: 0 for f in FIELDS}

    for i, rec in enumerate(cases, 1):
        status, body = http_get(rec["query"])
        d = derive(body) or {}
        now = {
            "status": status,
            "track_length": d.get("track_length"),
            "filtered_ascend": d.get("filtered_ascend"),
            "plain_ascend": d.get("plain_ascend"),
            "cost": d.get("cost"),
            "coordinates": d.get("coordinates"),
            "messages": d.get("messages"),
            "sha256": sha256_hex(body),
        }
        diffs = [f for f in FIELDS if now[f] != rec.get(f)]
        if diffs:
            mismatched.append(rec["id"])
            for f in diffs:
                per_field[f] += 1
            lines.append("CASE %s  %s  %s  query=%s" %
                         (rec["id"], rec["region"], rec["profile"],
                          rec.get("query")))
            for f in diffs:
                lines.append("  %-16s expected %-22r got %r" % (f, rec.get(f), now[f]))
            if args.bodies:
                with open(os.path.join(bodies_dir, "%s.geojson" % rec["id"]), "wb") as fh:
                    fh.write(body)
        if i % 50 == 0:
            print("  %d/%d" % (i, len(cases)), file=sys.stderr)

    header = [
        "BRouter oracle corpus check",
        "brouter_version: %s" % index.get("brouter_version"),
        "cases: %d   mismatched: %d" % (len(cases), len(mismatched)),
        "per field: %s" % ", ".join("%s=%d" % (f, per_field[f]) for f in FIELDS
                                    if per_field[f]),
        "",
    ]
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(header + lines) + "\n")

    for line in header:
        print(line, file=sys.stderr)
    for line in lines[:60]:
        print(line, file=sys.stderr)
    if len(lines) > 60:
        print("  ... %d more lines in %s" % (len(lines) - 60, args.out), file=sys.stderr)
    print("diff written to %s" % args.out, file=sys.stderr)

    return 1 if mismatched else 0


if __name__ == "__main__":
    raise SystemExit(main())
