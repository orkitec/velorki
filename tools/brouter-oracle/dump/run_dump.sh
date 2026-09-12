#!/usr/bin/env bash
# Compile (once) and run the single-file Java dump tool against the pinned
# upstream jar. Works from any cwd.
#
#   ./dump/run_dump.sh dump-microcache <tile.rd5|tilename> <lon> <lat> [--profile <f.brf>] [--geometry]
#   ./dump/run_dump.sh eval-profile <profile.brf|name> <tagsfile>
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
  *)
    echo "usage: run_dump.sh {dump-microcache|eval-profile} ..." >&2; exit 2 ;;
esac

exec "$JAVA" -Xmx256M -cp "$BROUTER_JAR:$CLASSES" Dump "${args[@]}"
