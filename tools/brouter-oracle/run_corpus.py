#!/usr/bin/env python3
"""Record the corpus: issue every request in corpus/requests.json against the
running RouteServer, store the full response body and an index of the derived
numbers.

Writes:
  corpus/responses/<id>.geojson   the verbatim response body
  corpus/index.json               per case: id, query, status, track-length,
                                  filtered ascend, plain-ascend, coordinate
                                  count, message count and the body sha256

Usage: python3 run_corpus.py [--only <id-prefix>]
"""

from __future__ import annotations

import argparse
import os
import sys

from oracle_common import (
    INDEX_JSON,
    REQUESTS_JSON,
    RESPONSES_DIR,
    derive,
    dump_json,
    http_get,
    load_json,
    sha256_hex,
    wait_for_server,
)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=None, help="only ids starting with this prefix")
    args = ap.parse_args()

    wait_for_server()
    doc = load_json(REQUESTS_JSON)
    cases = doc["cases"]
    if args.only:
        cases = [c for c in cases if c["id"].startswith(args.only)]

    os.makedirs(RESPONSES_DIR, exist_ok=True)
    keep = set()
    entries = []
    total_bytes = 0
    failures = 0

    for i, case in enumerate(cases, 1):
        status, body = http_get(case["query"])
        name = "%s.geojson" % case["id"]
        keep.add(name)
        with open(os.path.join(RESPONSES_DIR, name), "wb") as fh:
            fh.write(body)
        total_bytes += len(body)
        d = derive(body) or {}
        if status != 200 or not d:
            failures += 1
            print("  FAIL %s http=%s %s" % (case["id"], status,
                                            body[:120].decode("utf-8", "replace")),
                  file=sys.stderr)
        entries.append({
            "id": case["id"],
            "kind": case["kind"],
            "region": case["region"],
            "profile": case["profile"],
            "query": case["query"],
            "status": status,
            "track_length": d.get("track_length"),
            "filtered_ascend": d.get("filtered_ascend"),
            "plain_ascend": d.get("plain_ascend"),
            "cost": d.get("cost"),
            "coordinates": d.get("coordinates"),
            "messages": d.get("messages"),
            "bytes": len(body),
            "sha256": sha256_hex(body),
            "response": "responses/%s" % name,
        })
        if i % 25 == 0:
            print("  %d/%d" % (i, len(cases)), file=sys.stderr)

    if not args.only:
        # drop responses of cases that no longer exist
        for stale in sorted(set(os.listdir(RESPONSES_DIR)) - keep):
            if stale.endswith(".geojson"):
                os.remove(os.path.join(RESPONSES_DIR, stale))

    index = {
        "brouter_version": doc["brouter_version"],
        "seed": doc["seed"],
        "counts": doc["counts"],
        "total_response_bytes": total_bytes,
        "cases": entries,
    }
    if args.only:
        print("partial run (--only %s): index.json NOT rewritten" % args.only, file=sys.stderr)
    else:
        dump_json(INDEX_JSON, index)

    print("recorded %d cases, %d failures, %.2f MB of responses"
          % (len(entries), failures, total_bytes / 1e6), file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
