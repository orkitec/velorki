#!/usr/bin/env bash
# Compile (once) and run the single-file Java dump tool against the pinned
# upstream jar. Works from any cwd.
#
#   ./dump/run_dump.sh dump-microcache <tile.rd5|tilename> <lon> <lat> [--profile <f.brf>] [--geometry]
#   ./dump/run_dump.sh eval-profile <profile.brf|name> <tagsfile>
#   ./dump/run_dump.sh codec-vectors <outdir>
#   ./dump/run_dump.sh microcache-bytes <tile.rd5|tilename> <lon> <lat> <outfile>
#   ./dump/run_dump.sh microcache-listing <tile.rd5|tilename> <lon> <lat> [--bodies <n>]
#   ./dump/run_dump.sh osmfile-index <tile.rd5|tilename>
#   ./dump/run_dump.sh nodes-cache-walk [<segmentsdir>] <lon> <lat> <lon2> <lat2> [--maxmem <bytes>] [--no-direct-weaving] [--cleanup-mode <n>] [--steps <n>]
#
# A bare tile name (W20_N30) is resolved inside .cache/segments4, a bare profile
# name (trekking) inside brouter/profiles -- the profiles are used in place, the
# oracle never copies them.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../common.sh"

[ -f "$BROUTER_JAR" ] || { echo "no jar -- run ./fetch.sh first" >&2; exit 1; }

CLASSES="$CACHE_DIR/dumpclasses"
if [ ! -f "$CLASSES/Dump.class" ] || [ "$HERE/Dump.java" -nt "$CLASSES/Dump.class" ]; then
  mkdir -p "$CLASSES"
  "$JAVAC" -nowarn -cp "$BROUTER_JAR" -d "$CLASSES" "$HERE/Dump.java"
fi

cmd="${1:-}"; shift || true
args=()
case "$cmd" in
  dump-microcache)
    tile="${1:-}"; shift || true
    case "$tile" in
      */*|*.rd5) ;;
      *) tile="$SEGMENTS_DIR/$tile.rd5" ;;
    esac
    # resolve a bare --profile name against the repo profiles dir as well
    rest=()
    while [ $# -gt 0 ]; do
      if [ "$1" = "--profile" ] && [ $# -ge 2 ]; then
        pf="$2"
        case "$pf" in */*|*.brf) ;; *) pf="$PROFILES_DIR/$pf.brf" ;; esac
        rest+=( --profile "$pf" ); shift 2
      else
        rest+=( "$1" ); shift
      fi
    done
    args=( dump-microcache "$tile" "${rest[@]}" --lookups "$PROFILES_DIR/lookups.dat" )
    ;;
  eval-profile)
    prof="${1:-}"; shift || true
    case "$prof" in
      */*|*.brf) ;;
      *) prof="$PROFILES_DIR/$prof.brf" ;;
    esac
    args=( eval-profile "$prof" "$@" --lookups "$PROFILES_DIR/lookups.dat" )
    ;;
  codec-vectors)
    args=( codec-vectors "$@" )
    ;;
  microcache-bytes|microcache-listing|osmfile-index)
    tile="${1:-}"; shift || true
    case "$tile" in
      */*|*.rd5) ;;
      *) tile="$SEGMENTS_DIR/$tile.rd5" ;;
    esac
    args=( "$cmd" "$tile" "$@" )
    ;;
  nodes-cache-walk)
    # a segments dir may be given first; a bare number means "use .cache/segments4"
    case "${1:-}" in
      -*|[0-9]*) segdir="$SEGMENTS_DIR" ;;
      *) segdir="${1:-$SEGMENTS_DIR}"; shift || true ;;
    esac
    args=( nodes-cache-walk "$segdir" "$@" --lookups "$PROFILES_DIR/lookups.dat" )
    ;;
  *)
    echo "usage: run_dump.sh {dump-microcache|eval-profile|codec-vectors|microcache-bytes|microcache-listing|osmfile-index|nodes-cache-walk} ..." >&2; exit 2 ;;
esac

exec "$JAVA" -Xmx256M -cp "$BROUTER_JAR:$CLASSES" Dump "${args[@]}"
