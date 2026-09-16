#!/usr/bin/env bash
#
# BRouter segment mirror for Velorki.
#
# Mirrors https://brouter.de/brouter/segments4/*.rd5 into $SEGMENTS_DIR and
# writes $SEGMENTS_DIR/manifest.json describing what is on disk.
#
# Design notes:
#   * Safe to interrupt and re-run. Every download lands in "<tile>.rd5.part"
#     and is promoted with an atomic mv(1) only after its size matches the size
#     advertised by the directory index. Stale .part files are removed on start.
#   * Unchanged tiles are skipped twice over: first by comparing the local file
#     against the index (size + mtime), then by an If-Modified-Since request
#     (curl -z, the same mechanism as `wget --timestamping`). A tile that did
#     not change costs one conditional HEAD-sized round trip, not a download.
#   * Exactly one log line per tile.
#   * A flock ensures `sync-now` cannot race the periodic loop.
#
# Usage:  sync.sh once   -> one pass, then exit
#         sync.sh loop   -> pass, sleep $SYNC_INTERVAL, repeat (default)
set -uo pipefail

SEGMENTS_URL="${SEGMENTS_URL:-https://brouter.de/brouter/segments4/}"
SEGMENTS_DIR="${SEGMENTS_DIR:-/segments4}"
SEGMENT_FILTER="${SEGMENT_FILTER:-*}"
SYNC_INTERVAL="${SYNC_INTERVAL:-7d}"
MANIFEST_SHA256="${MANIFEST_SHA256:-0}"
BROUTER_VERSION="${BROUTER_VERSION:-v1.7.10}"
# The rd5 on-disk format is identified by the lookup version pair carried in
# misc/profiles2/lookups.dat ("---lookupversion:11" / "---minorversion:2").
# BRouter refuses to read a segment whose header version differs from the
# lookups.dat it was started with, so this pair *is* the format version.
RD5_FORMAT_VERSION_SET="${RD5_FORMAT_VERSION:+1}"   # explicit override wins
RD5_FORMAT_VERSION="${RD5_FORMAT_VERSION:-11.2}"

LOCK_FILE="$SEGMENTS_DIR/.sync.lock"
INDEX_FILE=""

log() { printf '%s [sync] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

cleanup() {
  [ -n "$INDEX_FILE" ] && rm -f "$INDEX_FILE"
  return 0
}
trap cleanup EXIT

# Turn "7d" / "12h" / "30m" / "3600" into seconds.
parse_interval() {
  local v="$1" n u
  n="${v%[dhms]}"
  u="${v#"$n"}"
  case "$n" in
    ''|*[!0-9]*) echo "invalid SYNC_INTERVAL: $v" >&2; return 1 ;;
  esac
  case "$u" in
    d) echo $(( n * 86400 )) ;;
    h) echo $(( n * 3600 )) ;;
    m) echo $(( n * 60 )) ;;
    s|'') echo "$n" ;;
    *) echo "invalid SYNC_INTERVAL unit: $v" >&2; return 1 ;;
  esac
}

# $SEGMENT_FILTER is a space-separated list of globs. It must be split on
# whitespace but NOT pathname-expanded: the default value is "*" (= planet), and
# an unguarded `for g in $SEGMENT_FILTER` would expand that against the process'
# working directory and silently match nothing. `set -f` disables globbing for
# the split; inside `case` the pattern is matched as a pattern, not expanded.
FILTER_PATS=()
split_filter() {
  set -f
  # shellcheck disable=SC2206  # deliberate word splitting, globbing disabled
  FILTER_PATS=( $SEGMENT_FILTER )
  set +f
  if [ "${#FILTER_PATS[@]}" -eq 0 ]; then
    log "FATAL SEGMENT_FILTER is empty; use '*' for the whole planet"
    return 1
  fi
}

# Does a tile name match any glob in $SEGMENT_FILTER?
matches_filter() {
  local tile="$1" g
  for g in "${FILTER_PATS[@]}"; do
    # shellcheck disable=SC2254  # $g is intentionally a glob pattern here
    case "$tile" in $g) return 0 ;; esac
  done
  return 1
}

human() {
  awk -v b="$1" 'BEGIN {
    if (b >= 1048576) printf "%.1fMB", b/1048576;
    else if (b >= 1024) printf "%.1fkB", b/1024;
    else printf "%dB", b;
  }'
}

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Reads the version pair from the lookups.dat published next to the tiles, so
# the manifest says what the tiles really are when upstream moves on. The
# default above is only a fallback for a mirror without the file.
detect_format_version() {
  [ -n "$RD5_FORMAT_VERSION_SET" ] && return 0
  local f="$SEGMENTS_DIR/lookups.dat" major minor
  if curl -fsSL --retry 3 --retry-delay 5 --max-time 120 \
        -A "velorki-brouter-updater" "${SEGMENTS_URL%/}/lookups.dat" -o "$f.part"; then
    mv -f "$f.part" "$f"
  else
    rm -f "$f.part"
  fi
  if [ ! -f "$f" ]; then
    log "WARN no lookups.dat on the mirror; formatVersion stays $RD5_FORMAT_VERSION"
    return 0
  fi
  major="$(sed -n 's/^---lookupversion:[[:space:]]*//p' "$f" | head -1 | tr -d '[:space:]')"
  minor="$(sed -n 's/^---minorversion:[[:space:]]*//p' "$f" | head -1 | tr -d '[:space:]')"
  if [ -n "$major" ] && [ -n "$minor" ]; then
    RD5_FORMAT_VERSION="$major.$minor"
    log "rd5 format version $RD5_FORMAT_VERSION (from lookups.dat)"
  else
    log "WARN lookups.dat has no version header; formatVersion stays $RD5_FORMAT_VERSION"
  fi
}

# ---------------------------------------------------------------- one pass ---
sync_once() {
  mkdir -p "$SEGMENTS_DIR" || { log "FATAL cannot create $SEGMENTS_DIR"; return 1; }

  exec 9>"$LOCK_FILE" || { log "FATAL cannot open lock $LOCK_FILE"; return 1; }
  if ! flock -n 9; then
    log "another sync is already running; nothing to do"
    return 0
  fi

  split_filter || return 1

  INDEX_FILE="$(mktemp)"
  log "fetching index $SEGMENTS_URL"
  if ! curl -fsSL --retry 3 --retry-delay 5 --max-time 120 \
        -A "velorki-brouter-updater" "$SEGMENTS_URL" -o "$INDEX_FILE"; then
    log "FATAL could not fetch the segment index"
    return 1
  fi

  # nginx autoindex rows look like:
  #   <a href="E5_N45.rd5">E5_N45.rd5</a>   12-Sep-2026 01:03   12134767
  local parsed
  parsed="$(sed -nE 's#^<a href="([^"/]+\.rd5)">[^<]*</a>[[:space:]]+([0-9]{2}-[A-Za-z]{3}-[0-9]{4} [0-9]{2}:[0-9]{2})[[:space:]]+([0-9]+).*$#\1\t\2\t\3#p' "$INDEX_FILE")"

  if [ -z "$parsed" ]; then
    log "FATAL index contained no .rd5 rows - did the mirror layout change?"
    return 1
  fi
  log "index lists $(printf '%s\n' "$parsed" | wc -l | tr -d ' ') tiles; filter='$SEGMENT_FILTER'"

  # Drop leftovers from a previous interrupted run.
  local stale
  stale="$(find "$SEGMENTS_DIR" -maxdepth 1 -name '*.part' -type f -print -delete 2>/dev/null | wc -l | tr -d ' ')"
  [ "$stale" != "0" ] && log "removed $stale stale .part file(s)"

  local n_ok=0 n_skip=0 n_fail=0 n_selected=0
  local name idxdate idxsize tile dst tmp idxepoch localsize localepoch code actual

  while IFS=$'\t' read -r name idxdate idxsize; do
    [ -n "$name" ] || continue
    tile="${name%.rd5}"
    matches_filter "$tile" || continue
    n_selected=$(( n_selected + 1 ))

    dst="$SEGMENTS_DIR/$name"
    tmp="$dst.part"

    # brouter.de states its index timestamps are map-snapshot time in CET.
    idxepoch="$(TZ=CET date -d "$idxdate" +%s 2>/dev/null || echo 0)"

    if [ -f "$dst" ]; then
      localsize="$(stat -c%s "$dst" 2>/dev/null || echo -1)"
      localepoch="$(stat -c%Y "$dst" 2>/dev/null || echo 0)"
      if [ "$localsize" = "$idxsize" ] && [ "$idxepoch" != "0" ] && [ "$localepoch" = "$idxepoch" ]; then
        log "$tile skip unchanged ($(human "$idxsize"))"
        n_skip=$(( n_skip + 1 ))
        continue
      fi
    fi

    # Conditional GET: -z against the local file is curl's If-Modified-Since,
    # the equivalent of `wget --timestamping`, so a tile that is byte-identical
    # but lost its mtime still does not get re-downloaded.
    rm -f "$tmp"
    if [ -f "$dst" ]; then
      code="$(curl -sSL --retry 3 --retry-delay 5 --max-time 3600 \
                -A "velorki-brouter-updater" \
                -z "$dst" -o "$tmp" -w '%{http_code}' "$SEGMENTS_URL$name" 2>/dev/null || echo 000)"
    else
      code="$(curl -sSL --retry 3 --retry-delay 5 --max-time 3600 \
                -A "velorki-brouter-updater" \
                -o "$tmp" -w '%{http_code}' "$SEGMENTS_URL$name" 2>/dev/null || echo 000)"
    fi

    if [ "$code" = "304" ]; then
      rm -f "$tmp"
      [ "$idxepoch" != "0" ] && touch -d "@$idxepoch" "$dst" 2>/dev/null
      log "$tile skip not-modified ($(human "$idxsize"))"
      n_skip=$(( n_skip + 1 ))
      continue
    fi

    if [ "$code" != "200" ]; then
      rm -f "$tmp"
      log "$tile FAIL http $code"
      n_fail=$(( n_fail + 1 ))
      continue
    fi

    actual="$(stat -c%s "$tmp" 2>/dev/null || echo -1)"
    if [ "$actual" != "$idxsize" ]; then
      rm -f "$tmp"
      log "$tile FAIL size mismatch (got $actual, index says $idxsize)"
      n_fail=$(( n_fail + 1 ))
      continue
    fi

    # Atomic promote: same filesystem, so mv is a rename(2). A reader either
    # sees the old complete file or the new complete file, never a partial one.
    if ! mv -f "$tmp" "$dst"; then
      rm -f "$tmp"
      log "$tile FAIL could not install"
      n_fail=$(( n_fail + 1 ))
      continue
    fi
    [ "$idxepoch" != "0" ] && touch -d "@$idxepoch" "$dst" 2>/dev/null

    log "$tile ok $(human "$actual")"
    n_ok=$(( n_ok + 1 ))
  done <<< "$parsed"

  if [ "$n_selected" = "0" ]; then
    log "WARNING SEGMENT_FILTER='$SEGMENT_FILTER' matched no tile in the index"
  fi

  detect_format_version
  write_manifest
  log "done: $n_ok downloaded, $n_skip unchanged, $n_fail failed, $n_selected selected"

  [ "$n_fail" = "0" ] || return 1
  return 0
}

# ------------------------------------------------------------- manifest.json ---
# Shape:
#   {
#     "formatVersion": "11.2",   <- rd5 lookup version from lookups.dat
#     "brouterVersion": "v1.7.10",
#     "generatedAt": "...", "source": "...", "segmentFilter": "...",
#     "tileCount": N, "totalBytes": N,
#     "tiles": [ { "tile": "E5_N45", "bytes": 123, "updatedAt": "ISO",
#                  "gazetteer": { "bytes": 1, "sha256": "..", "updatedAt": "ISO" } } ]
#   }
# The "gazetteer" object appears only for a tile that has an offline search
# file "<TILE>.gaz" next to its rd5 (tools/gazetteer builds them); its sha256
# is always written.
# sha256 per tile is omitted by default: hashing ~10 GB on every pass costs
# minutes of CPU for no benefit, since the size check against the index plus the
# atomic rename already rule out truncated files. Set MANIFEST_SHA256=1 to
# include it.
write_manifest() {
  local out="$SEGMENTS_DIR/manifest.json"
  local tmp="$out.part"
  local first=1 f base bytes updated sha total=0 count=0 gaz gazjson

  {
    printf '{\n'
    printf '  "formatVersion": "%s",\n' "$(json_escape "$RD5_FORMAT_VERSION")"
    printf '  "brouterVersion": "%s",\n' "$(json_escape "$BROUTER_VERSION")"
    printf '  "source": "%s",\n' "$(json_escape "$SEGMENTS_URL")"
    printf '  "segmentFilter": "%s",\n' "$(json_escape "$SEGMENT_FILTER")"
    printf '  "generatedAt": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "tiles": [\n'
    for f in "$SEGMENTS_DIR"/*.rd5; do
      [ -f "$f" ] || continue
      base="$(basename "$f")"
      bytes="$(stat -c%s "$f")"
      updated="$(date -u -d "@$(stat -c%Y "$f")" +%Y-%m-%dT%H:%M:%SZ)"
      total=$(( total + bytes ))
      count=$(( count + 1 ))
      [ "$first" = "1" ] || printf ',\n'
      first=0
      # An offline gazetteer next to the rd5 is optional; it is always hashed,
      # because the files are a few MB at most.
      gaz="${f%.rd5}.gaz"
      gazjson=""
      if [ -f "$gaz" ]; then
        gazjson="$(printf ', "gazetteer": { "bytes": %s, "sha256": "%s", "updatedAt": "%s" }' \
          "$(stat -c%s "$gaz")" \
          "$(sha256sum "$gaz" | cut -d' ' -f1)" \
          "$(date -u -d "@$(stat -c%Y "$gaz")" +%Y-%m-%dT%H:%M:%SZ)")"
      fi
      if [ "$MANIFEST_SHA256" = "1" ]; then
        sha="$(sha256sum "$f" | cut -d' ' -f1)"
        printf '    { "tile": "%s", "bytes": %s, "updatedAt": "%s", "sha256": "%s"%s }' \
          "${base%.rd5}" "$bytes" "$updated" "$sha" "$gazjson"
      else
        printf '    { "tile": "%s", "bytes": %s, "updatedAt": "%s"%s }' \
          "${base%.rd5}" "$bytes" "$updated" "$gazjson"
      fi
    done
    [ "$first" = "1" ] || printf '\n'
    printf '  ],\n'
    printf '  "tileCount": %s,\n' "$count"
    printf '  "totalBytes": %s\n' "$total"
    printf '}\n'
  } > "$tmp"

  mv -f "$tmp" "$out"
  log "manifest.json written ($count tiles, $(human "$total"))"
}

# -------------------------------------------------------------------- main ---
main() {
  local mode="${1:-loop}"
  local interval

  case "$mode" in
    once)
      sync_once
      ;;
    loop)
      interval="$(parse_interval "$SYNC_INTERVAL")" || exit 2
      log "starting; interval=$SYNC_INTERVAL (${interval}s) dir=$SEGMENTS_DIR"
      while true; do
        sync_once || log "pass finished with errors; will retry next cycle"
        log "sleeping ${interval}s"
        # Background sleep + wait so SIGTERM from `docker stop` lands promptly.
        sleep "$interval" &
        wait $! || true
      done
      ;;
    *)
      echo "usage: sync.sh [once|loop]" >&2
      exit 2
      ;;
  esac
}

main "$@"
