#!/usr/bin/env bash
# Download everything the oracle needs into .cache/ (git-ignored):
#   - the pinned BRouter release zip, and the fat jar extracted from it
#   - the rd5 segment tiles listed in tiles.txt
#
# Usage: ./fetch.sh [--verify-only]
#   --verify-only  never download anything, only verify what is already cached
#
# Exit codes: 0 ok, 1 hard failure, 3 tiles fetched but checksums differ from
# tiles.sha256 (brouter.de rebuilds the segments nightly -- see README).
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

mkdir -p "$CACHE_DIR" "$SEGMENTS_DIR" "$ZIP_DIR" "$CUSTOM_PROFILES_DIR"

say() { printf '%s\n' "$*" >&2; }

# ---------------------------------------------------------------- release zip
if [ ! -f "$BROUTER_ZIP" ]; then
  say "==> resolving the release asset for $BROUTER_VERSION via the GitHub API"
  api="https://api.github.com/repos/abrensch/brouter/releases/tags/${BROUTER_VERSION}"
  auth=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi
  asset_url="$(curl -fsSL "${auth[@]}" "$api" \
    | python3 -c '
import json,sys
rel = json.load(sys.stdin)
want = sys.argv[1]
for a in rel.get("assets", []):
    if a["name"] == want:
        print(a["browser_download_url"]); break
else:
    sys.exit("asset %s not found in release %s" % (want, rel.get("tag_name")))
' "brouter-${BROUTER_VERSION_NUM}.zip")"
  if [ "$asset_url" != "$BROUTER_ZIP_URL" ]; then
    say "note: API asset URL ($asset_url) differs from the pinned URL ($BROUTER_ZIP_URL); using the API one"
  fi
  say "==> downloading $asset_url"
  curl -fsSL --retry 3 -o "$BROUTER_ZIP.part" "$asset_url"
  mv "$BROUTER_ZIP.part" "$BROUTER_ZIP"
fi
say "    zip: $BROUTER_ZIP ($(stat -c%s "$BROUTER_ZIP") bytes, sha256 $(sha256sum "$BROUTER_ZIP" | cut -d' ' -f1))"

# ------------------------------------------------------------------- fat jar
# 1.7.10 ships the fat jar at the top of the zip as brouter-1.7.10-all.jar
# (there is no brouter-server/build/libs/ inside the release artifact).
if [ ! -f "$BROUTER_JAR" ]; then
  say "==> extracting the server jar"
  if ! unzip -l "$BROUTER_ZIP" | grep -q " $JAR_IN_ZIP\$"; then
    say "ERROR: $JAR_IN_ZIP not found in the zip. Contents:"
    unzip -l "$BROUTER_ZIP" | grep -E '\.jar$' >&2
    exit 1
  fi
  unzip -o -q "$BROUTER_ZIP" "$JAR_IN_ZIP" "brouter-${BROUTER_VERSION_NUM}/profiles2/*" -d "$ZIP_DIR"
fi
main_class="$(unzip -p "$BROUTER_JAR" META-INF/MANIFEST.MF | tr -d '\r' | sed -n 's/^Main-Class: //p')"
say "    jar: $BROUTER_JAR (Main-Class: $main_class)"

# --------------------------------------------------------------------- tiles
rc=0
while read -r tile _rest; do
  case "$tile" in ''|'#'*) continue ;; esac
  dest="$SEGMENTS_DIR/$tile.rd5"
  if [ ! -f "$dest" ] && [ "${1:-}" = "--verify-only" ]; then
    say "    MISSING $tile.rd5 (--verify-only, not downloading)"
    rc=1
    continue
  fi
  if [ ! -f "$dest" ]; then
    say "==> downloading $tile.rd5"
    curl -fsSL --retry 3 -o "$dest.part" "$SEGMENTS_BASE_URL/$tile.rd5"
    mv "$dest.part" "$dest"
  fi
  say "    $tile.rd5 $(stat -c%s "$dest") bytes"
done < "$ORACLE_DIR/tiles.txt"

# ----------------------------------------------------------------- checksums
say "==> verifying against tiles.sha256"
if ( cd "$SEGMENTS_DIR" && sha256sum --quiet -c "$ORACLE_DIR/tiles.sha256" ); then
  say "    checksums match the recorded data snapshot"
else
  rc=3
  say ""
  say "WARNING: the downloaded rd5 tiles do NOT match tools/brouter-oracle/tiles.sha256."
  say "brouter.de rebuilds segments4 nightly, so this is expected to happen eventually."
  say "The recorded corpus in corpus/ is only valid for the checksums in tiles.sha256."
  say "Actual checksums now:"
  ( cd "$SEGMENTS_DIR" && sha256sum ./*.rd5 ) >&2
  say ""
  say "To re-bind the corpus to the new data snapshot:"
  say "  cd tools/brouter-oracle"
  say "  (cd .cache/segments4 && sha256sum *.rd5) > tiles.sha256"
  say "  # update the byte sizes and the index timestamp in tiles.txt and README.md"
  say "  ./serve.sh && python3 gen_corpus.py && python3 run_corpus.py && ./stop.sh"
  say "  # then commit corpus/ together with the new tiles.sha256"
fi
exit $rc
