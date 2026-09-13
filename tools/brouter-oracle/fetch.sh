#!/usr/bin/env bash
# Put everything the oracle needs into .cache/ (git-ignored):
#   - the rd5 segment tiles listed in tiles.txt, copied from the committed
#     fixtures in tiles/ (see tiles/README.md) and verified against
#     tiles.sha256. No network: the bytes the corpus was recorded against are
#     in the repo. A tile that is listed but not committed is downloaded from
#     $SEGMENTS_BASE_URL as a fallback (used when re-recording against a newer
#     brouter.de snapshot).
#   - the pinned BRouter release zip, and the fat jar extracted from it
#
# Usage: ./fetch.sh [--verify-only] [--tiles-only]
#   --verify-only  never copy or download anything, only verify what is
#                  already cached in .cache/segments4
#   --tiles-only   skip the release zip and the jar (CI only needs the tiles;
#                  it never runs the Java oracle, and skipping the zip keeps the
#                  job off the GitHub API rate limit entirely)
#
# Exit codes: 0 ok, 1 hard failure (including a listed tile that is neither
# committed nor downloadable), 3 tiles present but checksums differ from
# tiles.sha256.
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
say "==> tiles from $TILES_DIR"
failed=0
bad_fixture=0
downloaded=0
tile_files=()
while read -r tile _rest; do
  case "$tile" in ''|'#'*) continue ;; esac
  dest="$SEGMENTS_DIR/$tile.rd5"
  src="$TILES_DIR/$tile.rd5"
  tile_files+=("$dest")

  if [ -f "$dest" ]; then
    say "    $tile.rd5 $(stat -c%s "$dest") bytes (already in $SEGMENTS_DIR)"
    continue
  fi

  if [ "$verify_only" -eq 1 ]; then
    say "    MISSING $tile.rd5 (--verify-only, not copying or downloading)"
    failed=1
    continue
  fi

  if [ -f "$src" ]; then
    # Verify the fixture where it lies: a committed file that does not match
    # tiles.sha256 must never reach $SEGMENTS_DIR in the first place.
    want="$(awk -v t="$tile.rd5" '$2 == t || $2 == "./" t {print $1}' "$ORACLE_DIR/tiles.sha256")"
    got="$(sha256sum "$src" | cut -d' ' -f1)"
    if [ -z "$want" ]; then
      say "    NOTE $tile.rd5 has no entry in tiles.sha256; nothing pins it"
    elif [ "$want" != "$got" ]; then
      say "    BAD FIXTURE $src"
      say "      tiles.sha256 wants $want"
      say "      the committed file is $got"
      bad_fixture=1
      continue
    fi
    cp -f "$src" "$dest.part"
    mv "$dest.part" "$dest"
    say "    $tile.rd5 $(stat -c%s "$dest") bytes (copied from $TILES_DIR)"
    continue
  fi

  # Not committed: fall back to a download. This is the re-recording path, not
  # the one CI takes -- whatever arrives is still checked against tiles.sha256.
  say "==> $tile.rd5 is not in $TILES_DIR; downloading from $SEGMENTS_BASE_URL"
  if ! curl -fsSL --retry 3 -o "$dest.part" "$SEGMENTS_BASE_URL/$tile.rd5"; then
    rm -f "$dest.part"
    say "    FAILED to download $SEGMENTS_BASE_URL/$tile.rd5"
    failed=1
    continue
  fi
  mv "$dest.part" "$dest"
  downloaded=1
  say "    $tile.rd5 $(stat -c%s "$dest") bytes (downloaded)"
done < "$ORACLE_DIR/tiles.txt"

if [ "$failed" -ne 0 ]; then
  say ""
  if [ "$verify_only" -eq 1 ]; then
    say "ERROR: --verify-only, and $SEGMENTS_DIR does not hold every tile in"
    say "tiles.txt. Run ./fetch.sh --tiles-only to seed it from $TILES_DIR."
  else
    say "ERROR: a tile listed in tiles.txt is neither committed in"
    say "  $TILES_DIR"
    say "nor downloadable from"
    say "  $SEGMENTS_BASE_URL"
    say "The tiles the corpus was recorded against are committed, so this means"
    say "tiles.txt lists a tile that was never added, or a checkout is partial."
    say "Do NOT re-record the corpus to work around it."
  fi
  quarantine "tile missing" ${tile_files[@]+"${tile_files[@]}"}
  exit 1
fi

if [ "$bad_fixture" -ne 0 ]; then
  say ""
  say "ERROR: a committed rd5 fixture in $TILES_DIR does not match"
  say "tools/brouter-oracle/tiles.sha256 (see above)."
  say "The corpus, corpus/responses/ and the brouter_dart vectors are bound to"
  say "exactly those bytes, so either the file was replaced without re-recording"
  say "or the checkout is damaged. Investigate before touching anything; see"
  say "$TILES_DIR/README.md."
  quarantine "committed fixture does not match tiles.sha256" ${tile_files[@]+"${tile_files[@]}"}
  exit 3
fi

# ----------------------------------------------------------------- checksums
say "==> verifying against tiles.sha256"
if ( cd "$SEGMENTS_DIR" && sha256sum --quiet -c "$ORACLE_DIR/tiles.sha256" ); then
  say "    checksums match the recorded data snapshot"
  exit 0
fi

say ""
say "ERROR: the rd5 tiles in $SEGMENTS_DIR do NOT match"
say "tools/brouter-oracle/tiles.sha256. Actual checksums now:"
( cd "$SEGMENTS_DIR" && sha256sum ./*.rd5 ) >&2
say ""
if [ "$downloaded" -ne 0 ]; then
  say "At least one tile was downloaded from $SEGMENTS_BASE_URL rather than taken"
  say "from $TILES_DIR. brouter.de rebuilds segments4 nightly, so a downloaded"
  say "tile is a *different* snapshot from the one the corpus was recorded"
  say "against -- that is expected, and it is why the tiles are committed."
else
  say "Nothing was downloaded: these bytes came from $SEGMENTS_DIR or from the"
  say "committed fixtures, so either the cache was tampered with or tiles.sha256"
  say "was edited without re-recording the corpus."
fi
say ""
say "To deliberately re-bind the corpus to a NEWER upstream snapshot:"
say "  1. cd tools/brouter-oracle"
say "     rm -rf .cache/segments4 tiles/*.rd5"
say "     ./fetch.sh --tiles-only      # now downloads from $UPSTREAM_SEGMENTS_URL"
say "     cp .cache/segments4/*.rd5 tiles/"
say "  2. (cd .cache/segments4 && sha256sum *.rd5) > tiles.sha256"
say "     # update the byte sizes and the index timestamp in tiles.txt,"
say "     # README.md and tiles/README.md"
say "  3. ./serve.sh && python3 gen_corpus.py && python3 run_corpus.py && ./stop.sh"
say "  4. re-record the brouter_dart vectors, then commit tiles/, corpus/, the"
say "     vectors and the new tiles.sha256 together"
quarantine "checksum mismatch" ${tile_files[@]+"${tile_files[@]}"}
exit 3
