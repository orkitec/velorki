#!/usr/bin/env python3
"""Serves the web planner locally the way Cloudflare Pages will.

    flutter build web --wasm --no-web-resources-cdn --dart-define-from-file=env/web.json
    python3 tool/web_serve.py [--port 8080] [--dir build/web] [--cache DIR]
    python3 tool/web_serve.py --https [--port 8443]

then open http://localhost:8080 (or https://localhost:8443) in Chrome.

- The build's own `_headers` (cross-origin isolation, CSP) are sent with
  every file, as Pages does.
- `/tiles/...` stands in for the Pages Function in deploy/cloudflare:
  `/tiles/latest.json` is the mirror's pointer from velorki-data with every
  release URL rewritten to this server, and `/tiles/<tag>/<file>` fetches the
  release asset from GitHub (following its redirect). Fetched tiles are kept
  in --cache (default build/web_tile_cache) so a restart does not fetch them
  again.
- `POST /cloudkit/upload?url=...` stands in for the Pages Function of the
  same name (CloudKit's upload host allows no CORS for our origin): the
  body goes to Apple's upload URL, and Apple's JSON comes back. Same
  checks as deploy/cloudflare/pages/cloudkit_upload.mjs.
- `--https` serves https on 8443, the origin the CloudKit Development token
  and the Google web client allow (Apple's console takes https origins
  only), so iCloud and Google sign-in can be tried locally. The certificate
  is mkcert's for localhost when mkcert is installed (`brew install mkcert`,
  `mkcert -install` once: Chrome then trusts it), else a self-signed one made
  with openssl, which Chrome warns about once ("Proceed to localhost"). Both
  are kept in --cert-dir (default build/web_cert). Past that warning the
  page may fetch, but a shared worker may not, so the database opens in
  the page rather than in drift's shared worker (`connection_web.dart`
  says so in the console); with mkcert's certificate it runs as on
  app.velorki.com.
- The relay at api.velorki.com answers CORS for https://app.velorki.com
  only (production's `CORS_ORIGINS`): from here AI, route weather and
  share links fail; sync and the rest do not need the relay. To try them,
  build against a relay of your own over https (`docs/SELF_HOSTING.md`)
  whose `CORS_ORIGINS` names https://localhost:8443, with its host in
  `web/_headers`' connect-src.
"""
import argparse
import http.server
import json
import os
import re
import shutil
import ssl
import subprocess
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request

POINTER = "https://raw.githubusercontent.com/orkitec/velorki-data/main/latest.json"
RELEASES = "https://github.com/orkitec/velorki-data/releases/download/"
TAG = re.compile(r"^tiles-\d{8}(-s\d+)?$")
FILE = re.compile(r"^[EW]\d{1,3}_[NS]\d{1,2}\.(rd5|gaz)$|^manifest\.json$")
UPLOAD_HOST = re.compile(r"^(cws\.icloud-content\.com|p\d+-contentws\.icloud\.com)$")
MAX_UPLOAD = 16 * 1024 * 1024
LOCKS = {}
LOCKS_GUARD = threading.Lock()
AGENT = {"User-Agent": "velorki-web-serve (+https://github.com/orkitec/velorki)"}

args = argparse.ArgumentParser()
args.add_argument("--port", type=int)
args.add_argument("--dir", default="build/web")
args.add_argument("--cache", default="build/web_tile_cache")
args.add_argument("--https", action="store_true", help="serve https (default port 8443)")
args.add_argument("--cert-dir", default="build/web_cert")
opts = args.parse_args()
if opts.port is None:
    opts.port = 8443 if opts.https else 8080
SCHEME = "https" if opts.https else "http"
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

    def do_POST(self):
        parts = urllib.parse.urlsplit(self.path)
        if parts.path != "/cloudkit/upload":
            self.send_error(404)
            return
        target = urllib.parse.parse_qs(parts.query).get("url", [""])[0]
        u = urllib.parse.urlsplit(target)
        try:
            ok = (
                u.scheme == "https"
                and UPLOAD_HOST.match(u.hostname or "")
                and u.port in (None, 443)
                and not u.username
                and not u.password
                and not u.fragment
                and u.path.endswith("/singleFileUpload")
                and "tk" in urllib.parse.parse_qs(u.query)
            )
        except ValueError:
            ok = False
        if not ok:
            self.send_error(400, "not a CloudKit upload URL")
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_UPLOAD:
            self.send_error(413)
            return
        data = self.rfile.read(length)
        headers = {}
        if self.headers.get("Content-Type"):
            headers["Content-Type"] = self.headers["Content-Type"]
        try:
            with urllib.request.urlopen(
                urllib.request.Request(target, data=data, headers=headers, method="POST"),
                timeout=30,
            ) as r:
                status, answer = r.status, r.read(64 * 1024)
        except urllib.error.HTTPError as e:
            status, answer = e.code, e.read(64 * 1024)
        except OSError:
            self.send_error(502)
            return
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(answer)))
        self.end_headers()
        self.wfile.write(answer)

    def pointer(self):
        with urllib.request.urlopen(urllib.request.Request(POINTER, headers=AGENT)) as r:
            data = json.load(r)
        origin = f"{SCHEME}://{self.headers.get('Host')}"

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


def certificate():
    """A certificate and key for localhost: mkcert's where it is installed,
    else a self-signed one from openssl. Made once, then reused."""
    os.makedirs(opts.cert_dir, exist_ok=True)
    cert = os.path.join(opts.cert_dir, "localhost.pem")
    key = os.path.join(opts.cert_dir, "localhost-key.pem")
    if os.path.isfile(cert) and os.path.isfile(key):
        return cert, key
    if shutil.which("mkcert"):
        subprocess.run(
            ["mkcert", "-cert-file", cert, "-key-file", key, "localhost", "127.0.0.1", "::1"],
            check=True,
        )
    else:
        sys.stderr.write("mkcert not found: a self-signed certificate (Chrome warns once)\n")
        subprocess.run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "825",
                "-subj", "/CN=localhost",
                "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1",
                "-keyout", key, "-out", cert,
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    return cert, key


server = http.server.ThreadingHTTPServer(("127.0.0.1", opts.port), Handler)
if opts.https:
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(*certificate())
    server.socket = context.wrap_socket(server.socket, server_side=True)
print(f"Velorki web planner on {SCHEME}://localhost:{opts.port}  (Ctrl-C to stop)")
server.serve_forever()
