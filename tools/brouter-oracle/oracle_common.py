"""Shared helpers for the BRouter oracle corpus tools.

No third-party dependencies: stdlib only, so CI needs nothing but python3.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import time
import urllib.error
import urllib.request

ORACLE_DIR = os.path.dirname(os.path.abspath(__file__))
CORPUS_DIR = os.path.join(ORACLE_DIR, "corpus")
RESPONSES_DIR = os.path.join(CORPUS_DIR, "responses")
REQUESTS_JSON = os.path.join(CORPUS_DIR, "requests.json")
INDEX_JSON = os.path.join(CORPUS_DIR, "index.json")

PORT = int(os.environ.get("BROUTER_ORACLE_PORT", "17777"))
BASE_URL = "http://127.0.0.1:%d/brouter" % PORT

# Fixed seed: the whole corpus must be reproducible byte for byte.
SEED = 20260912


def request_url(query: str) -> str:
    return "%s?%s" % (BASE_URL, query)


def http_get(query: str, timeout: float = 300.0):
    """Issue one routing request. Returns (status, body_bytes).

    Accept-Encoding is pinned to identity so the recorded body hash is the hash
    of the plain JSON BRouter produced, not of a gzip stream.
    """
    req = urllib.request.Request(
        request_url(query),
        headers={
            "Accept-Encoding": "identity",
            "User-Agent": "velorki-brouter-oracle/1",
            "Connection": "close",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:  # BRouter answers 400 with a text reason
        return e.code, e.read()


def wait_for_server(attempts: int = 60, delay: float = 0.5) -> None:
    probe = "lonlats=-16.9095,32.6459%7C-16.9010,32.6480&profile=trekking&alternativeidx=0&format=geojson"
    for _ in range(attempts):
        try:
            status, _body = http_get(probe, timeout=10)
            if status == 200:
                return
        except Exception:
            pass
        time.sleep(delay)
    raise SystemExit("BRouter RouteServer is not answering on %s -- run ./serve.sh" % BASE_URL)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def derive(body: bytes):
    """Pull the parity-relevant numbers out of a geojson response body.

    Returns a dict, or None if the body is not a routable geojson answer.
    """
    try:
        doc = json.loads(body.decode("utf-8"))
        feat = doc["features"][0]
        props = feat["properties"]
        coords = feat["geometry"]["coordinates"]
    except Exception:
        return None
    if not coords:
        return None
    return {
        "track_length": props.get("track-length"),
        "filtered_ascend": props.get("filtered ascend"),
        "plain_ascend": props.get("plain-ascend"),
        "cost": props.get("cost"),
        "coordinates": len(coords),
        "messages": len(props.get("messages", []) or []),
    }


# ---------------------------------------------------------------- geometry --

def haversine_m(lon1, lat1, lon2, lat2) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def fmt_coord(v: float) -> str:
    """Six decimals is BRouter's own resolution (ilon/ilat are micro-degrees)."""
    return ("%.6f" % v).rstrip("0").rstrip(".")


def build_query(pairs) -> str:
    """Join ordered (key, value) pairs into a query string.

    BRouter's RoutingParamCollector.getUrlParams() URL-decodes the whole URL and
    then tokenises on '?&' and '='. So '|' has to be percent-encoded (it would
    otherwise be fine, but Java's URI handling rejects it), while ',' must stay
    literal. Nothing else needs escaping for the parameters we generate.
    """
    out = []
    for k, v in pairs:
        out.append("%s=%s" % (k, str(v).replace("|", "%7C")))
    return "&".join(out)


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def dump_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, indent=1, sort_keys=False, ensure_ascii=False)
        fh.write("\n")
