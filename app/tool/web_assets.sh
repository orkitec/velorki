#!/usr/bin/env bash
# Puts the two files the web build loads beside index.html and that are not
# Dart: drift's web worker and SQLite compiled to WebAssembly, both from the
# releases of the exact package versions in pubspec.lock, checked against
# the hashes below. Run before `flutter build web`; the files are
# git-ignored. Moving drift or sqlite3 in pubspec.lock means new hashes here.
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

# sqlite3 3.7.0 and drift 2.35.0, as in pubspec.lock.
fetch https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.7.0/sqlite3.wasm \
  sqlite3.wasm fbcd2e8214f9231ea961e1b7706a22dd1194cfbfe6f26f13841b5aa7a0be1a1f
fetch https://github.com/simolus3/drift/releases/download/drift-2.35.0/drift_worker.js \
  drift_worker.js df0066e75363a9bed59a14eedbbded421c1f5910f8379812df164716aa2e6eed
