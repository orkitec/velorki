#!/usr/bin/env bash
# Download everything the oracle needs into .cache/ (git-ignored):
#   - the pinned BRouter release zip, and the fat jar extracted from it
#   - the rd5 segment tiles listed in tiles.txt, from the immutable snapshot
#     release orkitec/velorki-data@$ORACLE_TILES_TAG (see README, "The tiles")
#
# Usage: ./fetch.sh [--verify-only] [--tiles-only]
#   --verify-only  never download anything, only verify what is already cached
#   --tiles-only   skip the release zip and the jar (CI only needs the tiles;
#                  it never runs the Java oracle, and skipping the zip keeps the
#                  job off the GitHub API rate limit entirely)
#
# Exit codes: 0 ok, 1 hard failure (including a tile that would not download),
# 3 tiles fetched but checksums differ from tiles.sha256.
#
# On either failure the tiles are moved out of .cache/segments4 into
# .cache/segments4-bad, so a caller that ignores the exit code still cannot run
# the parity tests against the wrong bytes -- brouter_dart's `tilesMissing`
# then reports the tiles as absent and the tile-backed tests skip.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

verify_only=0
tiles_only=0
for arg in "$@"; do
  case "$arg" in
    --verify-only) verify_only=1 ;;
    --tiles-only)  tiles_only=1 ;;
    *) printf 'unknown option: %s\n' "$arg" >&2; exit 1 ;;
  esac
done

mkdir -p "$CACHE_DIR" "$SEGMENTS_DIR" "$ZIP_DIR" "$CUSTOM_PROFILES_DIR"

say() { printf '%s\n' "$*" >&2; }

# Move the given files out of the segments dir so nothing can read them.
quarantine() {
  local why="$1" f; shift
  mkdir -p "$BAD_SEGMENTS_DIR"
  for f in "$@"; do
    [ -e "$f" ] || continue
    mv -f "$f" "$BAD_SEGMENTS_DIR/$(basename "$f")"
  done
  say "    moved the bad tiles to $BAD_SEGMENTS_DIR ($why);"
  say "    $SEGMENTS_DIR is now empty, so the tile-backed tests will skip"
}

if [ "$tiles_only" -eq 0 ]; then
# ---------------------------------------------------------------- release zip
if [ ! -f "$BROUTER_ZIP" ]; then
  # The pinned asset URL is the source of truth; the API is only consulted to
  # notice an upstream rename. A rate-limited or offline API must not break the
  # build, so a failure there falls back to the pinned URL.
  asset_url="$BROUTER_ZIP_URL"
  say "==> resolving the release asset for $BROUTER_VERSION via the GitHub API"
  api="https://api.github.com/repos/abrensch/brouter/releases/tags/${BROUTER_VERSION}"
  auth=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi
  if api_url="$(curl -fsSL "${auth[@]}" "$api" 2>/dev/null \
    | python3 -c '
import json,sys
rel = json.load(sys.stdin)
want = sys.argv[1]
for a in rel.get("assets", []):
    if a["name"] == want:
        print(a["browser_download_url"]); break
else:
    sys.exit("asset %s not found in release %s" % (want, rel.get("tag_name")))
' "brouter-${BROUTER_VERSION_NUM}.zip" 2>/dev/null)" && [ -n "$api_url" ]; then
    if [ "$api_url" != "$BROUTER_ZIP_URL" ]; then
      say "note: API asset URL ($api_url) differs from the pinned URL ($BROUTER_ZIP_URL); using the API one"
      asset_url="$api_url"
    fi
  else
    say "note: the GitHub API did not answer (rate limit or offline); using the pinned URL"
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
fi  # tiles_only

# --------------------------------------------------------------------- tiles
say "==> tiles from $SEGMENTS_BASE_URL"
failed=0
tile_files=()
while read -r tile _rest; do
  case "$tile" in ''|'#'*) continue ;; esac
  dest="$SEGMENTS_DIR/$tile.rd5"
  tile_files+=("$dest")
  if [ ! -f "$dest" ] && [ "$verify_only" -eq 1 ]; then
    say "    MISSING $tile.rd5 (--verify-only, not downloading)"
    failed=1
    continue
  fi
  if [ ! -f "$dest" ]; then
    say "==> downloading $tile.rd5"
    if ! curl -fsSL --retry 3 -o "$dest.part" "$SEGMENTS_BASE_URL/$tile.rd5"; then
      rm -f "$dest.part"
      say "    FAILED to download $SEGMENTS_BASE_URL/$tile.rd5"
      failed=1
      continue
    fi
    mv "$dest.part" "$dest"
  fi
  say "    $tile.rd5 $(stat -c%s "$dest") bytes"
done < "$ORACLE_DIR/tiles.txt"

if [ "$failed" -ne 0 ]; then
  say ""
  say "ERROR: the pinned oracle tiles could not be fetched from"
  say "  $SEGMENTS_BASE_URL"
  say "These are immutable release assets, so this is a transport or an"
  say "availability problem, never an upstream data change. Do NOT re-record the"
  say "corpus to work around it."
  quarantine "download failed" ${tile_files[@]+"${tile_files[@]}"}
  exit 1
fi

# ----------------------------------------------------------------- checksums
say "==> verifying against tiles.sha256"
if ( cd "$SEGMENTS_DIR" && sha256sum --quiet -c "$ORACLE_DIR/tiles.sha256" ); then
  say "    checksums match the recorded data snapshot ($ORACLE_TILES_TAG)"
  exit 0
fi

say ""
say "ERROR: the rd5 tiles do NOT match tools/brouter-oracle/tiles.sha256."
say "They were downloaded from the immutable snapshot release"
say "  $SEGMENTS_BASE_URL"
say "so a mismatch means one of: the release assets were replaced (they must"
say "never be), tiles.sha256 was edited without re-recording the corpus, or the"
say "download was corrupted. Actual checksums now:"
( cd "$SEGMENTS_DIR" && sha256sum ./*.rd5 ) >&2
say ""
say "This is NOT the nightly brouter.de rebuild any more -- that is exactly what"
say "pinning to $ORACLE_TILES_TAG removed. Investigate before touching anything."
say ""
say "To deliberately re-bind the corpus to a NEWER upstream snapshot:"
say "  1. download the new tiles from $UPSTREAM_SEGMENTS_URL"
say "  2. publish them as a new, immutable oracle-<date> release in"
say "     orkitec/velorki-data and point ORACLE_TILES_TAG in common.sh at it"
say "  3. cd tools/brouter-oracle"
say "     (cd .cache/segments4 && sha256sum *.rd5) > tiles.sha256"
say "     # update the byte sizes and the index timestamp in tiles.txt and README.md"
say "     ./serve.sh && python3 gen_corpus.py && python3 run_corpus.py && ./stop.sh"
say "  4. re-record the brouter_dart vectors, then commit corpus/, the vectors"
say "     and the new tiles.sha256 together"
quarantine "checksum mismatch" ${tile_files[@]+"${tile_files[@]}"}
exit 3
