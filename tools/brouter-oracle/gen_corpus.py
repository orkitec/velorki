#!/usr/bin/env python3
"""Generate corpus/requests.json: a deterministic set of BRouter requests.

The generator needs the RouteServer running (./serve.sh), for two reasons:

  * anchor points are sampled from the geometry of a handful of fixed
    "backbone" routes, so every anchor is guaranteed to sit on the real road
    network of the tile instead of in the Atlantic;
  * every candidate case is issued once and only kept if it actually routes
    (HTTP 200 with a non-empty geometry) and stays inside the size budget.

Everything is driven by one fixed seed and a fixed iteration order, so two runs
against the same rd5 snapshot produce a byte-identical requests.json.

Usage: python3 gen_corpus.py [--seed N]
"""

from __future__ import annotations

import argparse
import json
import random
import sys

from oracle_common import (
    REQUESTS_JSON,
    SEED,
    build_query,
    derive,
    dump_json,
    fmt_coord,
    haversine_m,
    http_get,
    wait_for_server,
)

# Profiles under test. All of them live in brouter/profiles/ in this repo and
# are served straight from there -- the oracle never copies a profile.
PROFILES = [
    "trekking",
    "fastbike",
    "fastbike-lowtraffic",
    "gravel",
    "mtb",
    "shortest",
]

# Fixed "backbone" routes whose geometry supplies the anchor points.
# Coordinates are lon,lat of well-known places on the two islands.
REGIONS = [
    {
        "name": "madeira",
        "tile": "W20_N30",
        "backbones": [
            ((-16.9085, 32.6485), (-16.7683, 32.7175)),   # Funchal -> Machico
            ((-16.9085, 32.6485), (-17.0622, 32.6742)),   # Funchal -> Ribeira Brava
            ((-16.9772, 32.6499), (-16.8814, 32.8007)),   # Camara de Lobos -> Santana
            ((-16.9085, 32.6485), (-16.8420, 32.6560)),   # Funchal -> Canico
        ],
        # start points for the round trips
        "roundtrip_starts": [(-16.9085, 32.6485), (-16.7683, 32.7175)],
    },
    {
        "name": "iceland",
        "tile": "W25_N60",
        "backbones": [
            ((-21.9266, 64.1417), (-21.9414, 64.0671)),   # Reykjavik -> Hafnarfjordur
            ((-21.9266, 64.1417), (-21.6900, 64.1670)),   # Reykjavik -> Mosfellsbaer
            ((-21.9266, 64.1417), (-21.8954, 64.1000)),   # Reykjavik -> Kopavogur
            ((-21.9414, 64.0671), (-22.5600, 64.0049)),   # Hafnarfjordur -> Keflavik
        ],
        "roundtrip_starts": [(-21.9266, 64.1417), (-21.9414, 64.0671)],
    },
]

# Pair/leg air distance window. Kept small on purpose: a geojson response is
# roughly 100 bytes per track point, and corpus/responses/ has to stay well
# under the ~15 MB the repository budgets for it.
MIN_LEG_M = 800.0
MAX_LEG_M = 4000.0
MAX_TRACK_LENGTH_M = 25000

# How many cases of each kind.
N_PAIRS = 120          # 6 profiles x 4 alternativeidx x 5
N_TRIPLES = 40
N_NOGOS = 24
N_ROUNDTRIPS = 16

ROUNDTRIP_RADII = [1200, 1800, 2500, 3000]
ROUNDTRIP_DIRECTIONS = [0, 90, 180, 270]


def fetch_geometry(a, b, profile="trekking"):
    q = build_query([
        ("lonlats", "%s,%s|%s,%s" % (fmt_coord(a[0]), fmt_coord(a[1]),
                                     fmt_coord(b[0]), fmt_coord(b[1]))),
        ("profile", profile),
        ("alternativeidx", 0),
        ("format", "geojson"),
    ])
    status, body = http_get(q)
    if status != 200:
        raise SystemExit("backbone request failed (%d): %s\n  %s"
                         % (status, body[:200].decode("utf-8", "replace"), q))
    doc = json.loads(body.decode("utf-8"))
    return [(c[0], c[1]) for c in doc["features"][0]["geometry"]["coordinates"]]


def collect_anchors(region, every=12):
    """Every Nth track point of every backbone, de-duplicated, in a fixed order."""
    anchors = []
    seen = set()
    for a, b in region["backbones"]:
        for i, (lon, lat) in enumerate(fetch_geometry(a, b)):
            if i % every:
                continue
            key = (round(lon, 6), round(lat, 6))
            if key in seen:
                continue
            seen.add(key)
            anchors.append(key)
    return anchors


def pick_partner(rng, anchors, a, tries=60):
    for _ in range(tries):
        b = anchors[rng.randrange(len(anchors))]
        d = haversine_m(a[0], a[1], b[0], b[1])
        if MIN_LEG_M <= d <= MAX_LEG_M:
            return b
    return None


def lonlats(points):
    return "|".join("%s,%s" % (fmt_coord(p[0]), fmt_coord(p[1])) for p in points)


def validate(query):
    """Issue the candidate once; return the derived numbers or None."""
    status, body = http_get(query)
    if status != 200:
        return None
    d = derive(body)
    if d is None:
        return None
    try:
        if int(d["track_length"]) > MAX_TRACK_LENGTH_M:
            return None
    except (TypeError, ValueError):
        return None
    return d


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=SEED)
    args = ap.parse_args()

    wait_for_server()
    rng = random.Random(args.seed)

    anchors = {}
    for region in REGIONS:
        anchors[region["name"]] = collect_anchors(region)
        print("region %-8s %d anchors" % (region["name"], len(anchors[region["name"]])),
              file=sys.stderr)

    cases = []
    rejected = 0

    def add(case):
        cases.append(case)

    # ----------------------------------------------------------- pair cases --
    combos = [(p, alt) for p in PROFILES for alt in (0, 1, 2, 3)]
    per_combo = N_PAIRS // len(combos)
    n = 0
    for profile, alt in combos:
        made = 0
        guard = 0
        while made < per_combo and guard < 400:
            guard += 1
            region = REGIONS[n % len(REGIONS)]
            pool = anchors[region["name"]]
            a = pool[rng.randrange(len(pool))]
            b = pick_partner(rng, pool, a)
            if b is None:
                rejected += 1
                continue
            q = build_query([
                ("lonlats", lonlats([a, b])),
                ("profile", profile),
                ("alternativeidx", alt),
                ("format", "geojson"),
            ])
            if validate(q) is None:
                rejected += 1
                continue
            add({"id": "pair-%03d" % n, "kind": "pair", "region": region["name"],
                 "profile": profile, "alternativeidx": alt,
                 "waypoints": [list(a), list(b)], "query": q})
            made += 1
            n += 1

    # --------------------------------------------------------- triple cases --
    n = 0
    guard = 0
    while len([c for c in cases if c["kind"] == "triple"]) < N_TRIPLES and guard < 800:
        guard += 1
        region = REGIONS[n % len(REGIONS)]
        profile = PROFILES[n % len(PROFILES)]
        pool = anchors[region["name"]]
        a = pool[rng.randrange(len(pool))]
        b = pick_partner(rng, pool, a)
        if b is None:
            rejected += 1
            continue
        c = pick_partner(rng, pool, b)
        if c is None or c == a:
            rejected += 1
            continue
        q = build_query([
            ("lonlats", lonlats([a, b, c])),
            ("profile", profile),
            ("alternativeidx", n % 4),
            ("format", "geojson"),
        ])
        if validate(q) is None:
            rejected += 1
            continue
        add({"id": "triple-%03d" % n, "kind": "triple", "region": region["name"],
             "profile": profile, "alternativeidx": n % 4,
             "waypoints": [list(a), list(b), list(c)], "query": q})
        n += 1

    # ----------------------------------------------------------- nogo cases --
    n = 0
    guard = 0
    while len([c for c in cases if c["kind"] == "nogo"]) < N_NOGOS and guard < 800:
        guard += 1
        region = REGIONS[n % len(REGIONS)]
        profile = PROFILES[n % len(PROFILES)]
        pool = anchors[region["name"]]
        a = pool[rng.randrange(len(pool))]
        b = pick_partner(rng, pool, a)
        if b is None:
            rejected += 1
            continue
        radius = [120, 200, 350][n % 3]
        mid = ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0)
        nogo = "%s,%s,%d" % (fmt_coord(mid[0]), fmt_coord(mid[1]), radius)
        q = build_query([
            ("lonlats", lonlats([a, b])),
            ("nogos", nogo),
            ("profile", profile),
            ("alternativeidx", 0),
            ("format", "geojson"),
        ])
        if validate(q) is None:
            rejected += 1
            continue
        add({"id": "nogo-%03d" % n, "kind": "nogo", "region": region["name"],
             "profile": profile, "alternativeidx": 0,
             "waypoints": [list(a), list(b)], "nogos": nogo, "query": q})
        n += 1

    # ------------------------------------------------------ round trip cases --
    # engineMode=4 is BROUTER_ENGINEMODE_ROUNDTRIP. roundTripDistance is the
    # RADIUS in metres to the generated circle points, not the total length.
    # `direction` is mandatory for us: without it RoutingEngine falls back to
    # getRandomDirectionFromData(), which ends in Math.random() -> not
    # reproducible. See README, "Determinism".
    n = 0
    guard = 0
    while len([c for c in cases if c["kind"] == "roundtrip"]) < N_ROUNDTRIPS and guard < 400:
        guard += 1
        region = REGIONS[n % len(REGIONS)]
        start = region["roundtrip_starts"][(n // 2) % len(region["roundtrip_starts"])]
        profile = PROFILES[n % len(PROFILES)]
        radius = ROUNDTRIP_RADII[n % len(ROUNDTRIP_RADII)]
        direction = ROUNDTRIP_DIRECTIONS[(n // 2) % len(ROUNDTRIP_DIRECTIONS)]
        q = build_query([
            ("lonlats", lonlats([start])),
            ("profile", profile),
            ("format", "geojson"),
            ("engineMode", 4),
            ("roundTripDistance", radius),
            ("direction", direction),
            ("roundTripPoints", 5),
        ])
        if validate(q) is None:
            rejected += 1
            n += 1
            continue
        add({"id": "roundtrip-%03d" % n, "kind": "roundtrip", "region": region["name"],
             "profile": profile, "waypoints": [list(start)],
             "roundTripDistance": radius, "direction": direction,
             "roundTripPoints": 5, "query": q})
        n += 1

    doc = {
        "generator": "gen_corpus.py",
        "seed": args.seed,
        "brouter_version": "v1.7.10",
        "note": "Deterministic corpus. Valid only for the rd5 snapshot recorded "
                "in tiles.sha256; see README.md.",
        "profiles": PROFILES,
        "counts": {},
        "cases": cases,
    }
    for c in cases:
        doc["counts"][c["kind"]] = doc["counts"].get(c["kind"], 0) + 1
    doc["counts"]["total"] = len(cases)

    dump_json(REQUESTS_JSON, doc)
    print("wrote %s: %d cases %s (%d candidates rejected)"
          % (REQUESTS_JSON, len(cases), doc["counts"], rejected), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
