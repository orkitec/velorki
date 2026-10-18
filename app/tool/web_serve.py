#!/usr/bin/env python3
"""Serves the web planner locally the way Cloudflare Pages will.

    flutter build web --wasm --no-web-resources-cdn --dart-define-from-file=env/web.json
    python3 tool/web_serve.py [--port 8080] [--dir build/web] [--cache DIR]

then open http://localhost:8080 in Chrome.

- The build's own `_headers` (cross-origin isolation, CSP) are sent with
  every file, as Pages does.
- `/tiles/...` stands in for the Pages Function in deploy/cloudflare:
  `/tiles/latest.json` is the mirror's pointer from velorki-data with every
  release URL rewritten to this server, and `/tiles/<tag>/<file>` fetches the
  release asset from GitHub (following its redirect). Fetched tiles are kept
  in --cache (default build/web_tile_cache) so a restart does not fetch them
  again.
"""
import argparse
import http.server
import json
import os
import re
import shutil
import sys
import threading
import urllib.request

POINTER = "https://raw.githubusercontent.com/orkitec/velorki-data/main/latest.json"
RELEASES = "https://github.com/orkitec/velorki-data/releases/download/"
TAG = re.compile(r"^tiles-\d{8}(-s\d+)?$")
FILE = re.compile(r"^[EW]\d{1,3}_[NS]\d{1,2}\.(rd5|gaz)$|^manifest\.json$")
LOCKS = {}
LOCKS_GUARD = threading.Lock()
AGENT = {"User-Agent": "velorki-web-serve (+https://github.com/orkitec/velorki)"}

args = argparse.ArgumentParser()
args.add_argument("--port", type=int, default=8080)
args.add_argument("--dir", default="build/web")
args.add_argument("--cache", default="build/web_tile_cache")
opts = args.parse_args()
os.makedirs(opts.cache, exist_ok=True)


def header_rules():
    """The build's Cloudflare `_headers` as (pattern, [(name, value)])."""
    rules, current = [], None
    try:
        lines = open(os.path.join(opts.dir, "_headers")).read().splitlines()
    except OSError:
        return rules
    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line[0].isspace():
            current = (line.strip(), [])
            rules.append(current)
        elif current is not None:
            name, value = line.strip().split(":", 1)
            current[1].append((name.strip(), value.strip()))
    return rules


RULES = header_rules()


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".mjs": "text/javascript",
        ".js": "text/javascript",
        ".json": "application/json",
    }

    def __init__(self, *a, **k):
        super().__init__(*a, directory=opts.dir, **k)

    def end_headers(self):
        path = self.path.split("?")[0]
        for pattern, headers in RULES:
            hit = path.startswith(pattern[:-1]) if pattern.endswith("*") else path == pattern
            if hit:
                for name, value in headers:
                    if name.lower() != "cache-control":
                        self.send_header(name, value)
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/tiles/latest.json":
            return self.pointer()
        m = re.match(r"^/tiles/([^/]+)/([^/]+)$", path)
        if m:
            return self.tile(m.group(1), m.group(2))
        return super().do_GET()

    def pointer(self):
        with urllib.request.urlopen(urllib.request.Request(POINTER, headers=AGENT)) as r:
            data = json.load(r)
        origin = f"http://{self.headers.get('Host')}"

        def rewrite(url):
            if isinstance(url, str) and url.startswith(RELEASES):
                tag = url[len(RELEASES):].rstrip("/")
                if TAG.match(tag):
                    return f"{origin}/tiles/{tag}/"
            return url

        if "baseUrl" in data:
            data["baseUrl"] = rewrite(data["baseUrl"])
        for shard in data.get("shards", []):
            if isinstance(shard, dict) and "baseUrl" in shard:
                shard["baseUrl"] = rewrite(shard["baseUrl"])
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def tile(self, tag, name):
        if not TAG.match(tag) or not FILE.match(name):
            self.send_error(404)
            return
        cached = os.path.join(opts.cache, tag, name)
        # One fetch per file: a second request for a file being fetched
        # waits for it and is then served from the cache.
        with LOCKS_GUARD:
            lock = LOCKS.setdefault(cached, threading.Lock())
        with lock:
            if not os.path.isfile(cached):
                self.fetch(tag, name, cached)
                return
        size = os.path.getsize(cached)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(size))
        self.end_headers()
        with open(cached, "rb") as f:
            shutil.copyfileobj(f, self.wfile, 1 << 20)

    def fetch(self, tag, name, cached):
        """Streams the release asset to the browser as it arrives (a tile is
        hundreds of MB; holding the answer back until it is all here runs
        into the app's receive timeout) and into the cache. A browser that
        goes away does not stop the cache from filling."""
        os.makedirs(os.path.dirname(cached), exist_ok=True)
        sys.stderr.write(f"fetching {tag}/{name} from GitHub…\n")
        request = urllib.request.Request(f"{RELEASES}{tag}/{name}", headers=AGENT)
        try:
            r = urllib.request.urlopen(request)
        except urllib.error.HTTPError as e:
            self.send_error(e.code)
            return
        client = True
        with r, open(cached + ".part", "wb") as out:
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            length = r.headers.get("Content-Length")
            if length:
                self.send_header("Content-Length", length)
            self.end_headers()
            while chunk := r.read(1 << 20):
                out.write(chunk)
                if client:
                    try:
                        self.wfile.write(chunk)
                    except OSError:
                        client = False
        os.replace(cached + ".part", cached)

    def log_message(self, fmt, *a):
        sys.stderr.write("%s\n" % (fmt % a))


print(f"Velorki web planner on http://localhost:{opts.port}  (Ctrl-C to stop)")
http.server.ThreadingHTTPServer(("127.0.0.1", opts.port), Handler).serve_forever()
