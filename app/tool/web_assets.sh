#!/usr/bin/env bash
# Puts the files the web build loads beside index.html that are not Dart and
# not fetched from a CDN at run time: drift's web worker and SQLite compiled
# to WebAssembly, from the releases of the exact package versions in
# pubspec.lock, and maplibre-gl-js (its ES modules, stylesheet and licence)
# at the version maplibre_gl_web is written against (kMapLibreJsVersion in
# its js_loader.dart), from the npm registry. Each is checked against the
# hash below. Run before `flutter build web`; the files are git-ignored.
# Moving drift, sqlite3 or maplibre_gl in pubspec.lock means new versions
# and hashes here.
set -euo pipefail
cd "$(dirname "$0")/../web"

fetch() {
  local url="$1" file="$2" want="$3"
  if [ -f "$file" ] && echo "$want  $file" | shasum -a 256 -c --status 2>/dev/null; then
    return
  fi
  echo "==> $file from $url"
  curl -fsSL --retry 3 -o "$file.part" "$url"
  if ! echo "$want  $file.part" | shasum -a 256 -c --status; then
    echo "::error::$file does not match its pinned sha256; see tool/web_assets.sh."
    rm -f "$file.part"
    exit 1
  fi
  mv "$file.part" "$file"
}

# sqlite3 3.7.1 and drift 2.35.2, as in pubspec.lock. The page itself loads
# sqlite3.wasm too (the gazetteer search, through package:sqlite3), so it
# follows pubspec's sqlite3. drift's release worker carries the Dart side of
# the sqlite3 version drift was built with (3.7.0 for 2.35.2), whose bindings
# are the same as 3.7.1's; when a bump changes sqlite3's lib/src/wasm, compile
# the worker against pubspec.lock instead:
#   dart compile js -O2 -o web/drift_worker.js <file calling
#   WasmDatabase.workerMainForOpen()>
fetch https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.7.1/sqlite3.wasm \
  sqlite3.wasm 87c1869b533ea4b6daa1f4dc6aa7e9cf3dae6e6ea53f8ed57080c08eb5f64303
fetch https://github.com/simolus3/drift/releases/download/drift-2.35.2/drift_worker.js \
  drift_worker.js 191fc9db018d2bbecb1723e81118fcf2c5c094df8644c2fcba2ed51df061e90a

# maplibre-gl-js 6.4.1 for maplibre_gl 0.27.1. The library finds its worker
# beside its own URL, so the dist files stay together in maplibre-gl/.
MAPLIBRE=6.4.1
if [ ! -f "maplibre-gl/.version-$MAPLIBRE" ]; then
  fetch "https://registry.npmjs.org/maplibre-gl/-/maplibre-gl-$MAPLIBRE.tgz" \
    maplibre-gl.tgz 21d78393afc6db78f1f9963dfd979057b536b309d8c48c1a4dde95277a522fef
  rm -rf maplibre-gl
  mkdir maplibre-gl
  tar -xzf maplibre-gl.tgz -C maplibre-gl --strip-components=2 \
    package/dist/maplibre-gl.mjs package/dist/maplibre-gl-shared.mjs \
    package/dist/maplibre-gl-worker.mjs package/dist/maplibre-gl.css
  tar -xzf maplibre-gl.tgz -C maplibre-gl --strip-components=1 package/LICENSE.txt
  rm maplibre-gl.tgz
  touch "maplibre-gl/.version-$MAPLIBRE"
fi
