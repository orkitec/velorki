#!/usr/bin/env bash
# Runs the emulator integration suite under integration_test/.
#
#   tool/itest.sh                       # every test, on emulator-5554
#   tool/itest.sh close_loop            # only the tests whose name matches
#   VELORKI_ITEST_DEVICE=... tool/itest.sh
#   VELORKI_ITEST_SHARD=1/3 tool/itest.sh   # one third of the files (CI)
#   VELORKI_ITEST_SHARD=1/3 VELORKI_ITEST_DRY_RUN=1 tool/itest.sh  # list only
#   VELORKI_ITEST_COMBINED=1 tool/itest.sh  # every file in one run (iOS CI)
#
# By default each file is a separate `flutter test` run — the integration_test
# binding installs one test build per invocation — and the first failure stops
# the script, because a red test usually means every later one is red too.
# That is what Android CI does, sharded three ways.
#
# VELORKI_ITEST_COMBINED=1 runs integration_test/all_tests.dart instead, which
# imports every file and groups them: one build, one install, one attach, all
# nine files in one process. It is what the iOS job runs, where the Xcode build
# and the simulator boot cost far more than the tests and were being paid once
# per file. A combined run needs a longer watchdog than one file does, so set
# VELORKI_ITEST_TIMEOUT with it (the iOS workflow uses 2400).
#
# Configuration is fixed here on purpose:
#   VELORKI_BROUTER_URL empty  -> nothing to route against but the device, so a
#                                 green run really proves the on-device engine
#   VELORKI_SEGMENTS_URL       -> the rd5 mirror the tests download their tile
#                                 from (10.0.2.2 is the host, seen from the
#                                 emulator)
#   VELORKI_API_URL empty      -> the relay-backed features stay hidden
#   VELORKI_ITEST_REGION       -> nyc (default) or madeira; picks the
#                                 coordinates and the tile, see
#                                 integration_test/support/region.dart
#   VELORKI_ITEST_SHARD=N/M    -> run only shard N of M. The files are spread
#                                 over the shards by the weights in
#                                 itest_weight below, heaviest first into the
#                                 lightest shard so far, which keeps the three
#                                 slow flows (close_loop, navigate_route,
#                                 record_ride) in three different shards. The
#                                 split depends only on the file names, so
#                                 every shard of a run agrees on it.
#   VELORKI_ITEST_COMBINED=1   -> one `flutter test` over
#                                 integration_test/all_tests.dart instead of
#                                 one per file. Rules out a file filter and a
#                                 shard: the combined entry point is the whole
#                                 suite or nothing.
#   VELORKI_ITEST_DRY_RUN=1    -> print the files this run would take and stop
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEVICE="${VELORKI_ITEST_DEVICE:-emulator-5554}"
SEGMENTS_URL="${VELORKI_SEGMENTS_URL:-http://10.0.2.2:8000}"
REGION="${VELORKI_ITEST_REGION:-nyc}"
filter="${1:-}"

# plan_route_test.dart is the one test that wants a BRouter *server* (the
# oracle harness in tools/brouter-oracle, on 10.0.2.2:17777). It is skipped
# unless VELORKI_BROUTER_URL says where that server is; everything else here
# routes on the device by design.
BROUTER_URL="${VELORKI_BROUTER_URL:-}"

tests=()
skipped=()
for f in integration_test/*_test.dart; do
  [ -e "$f" ] || continue
  if [ -n "$filter" ] && [[ "$f" != *"$filter"* ]]; then continue; fi
  if [ "$(basename "$f")" = plan_route_test.dart ] && [ -z "$BROUTER_URL" ]; then
    skipped+=("$f")
    continue
  fi
  tests+=("$f")
done

if [ ${#tests[@]} -eq 0 ]; then
  printf 'no integration tests match %q\n' "$filter" >&2
  exit 1
fi

# How expensive a file is, relative to the others: only the ratio matters, and
# only for spreading the files over the shards. A file nobody weighed counts
# as 1, so adding a test file needs no change here unless it is slow.
itest_weight() {
  case "$(basename "$1")" in
    close_loop_test.dart | navigate_route_test.dart | record_ride_test.dart) echo 2 ;;
    *) echo 1 ;;
  esac
}

SHARD="${VELORKI_ITEST_SHARD:-}"
if [ -n "$SHARD" ]; then
  if [[ ! "$SHARD" =~ ^[0-9]+/[0-9]+$ ]]; then
    printf 'VELORKI_ITEST_SHARD must look like 1/3, not %q\n' "$SHARD" >&2
    exit 2
  fi
  shard_index="${SHARD%%/*}"
  shard_count="${SHARD##*/}"
  if [ "$shard_index" -lt 1 ] || [ "$shard_count" -lt 1 ] \
    || [ "$shard_index" -gt "$shard_count" ]; then
    printf 'VELORKI_ITEST_SHARD %q is out of range\n' "$SHARD" >&2
    exit 2
  fi

  # Heaviest file first, name second so the order never depends on the file
  # system; then each file goes to the shard with the least work on it, ties
  # to the lowest-numbered shard.
  loads=()
  for ((i = 0; i < shard_count; i++)); do loads+=(0); done
  mine=()
  while IFS=$'\t' read -r w f; do
    least=0
    for ((i = 1; i < shard_count; i++)); do
      if [ "${loads[i]}" -lt "${loads[least]}" ]; then least=$i; fi
    done
    loads[least]=$((loads[least] + w))
    if [ "$least" -eq $((shard_index - 1)) ]; then mine+=("$f"); fi
  done < <(
    for f in "${tests[@]}"; do printf '%s\t%s\n' "$(itest_weight "$f")" "$f"; done \
      | LC_ALL=C sort -t$'\t' -k1,1nr -k2,2
  )

  tests=(${mine[@]+"${mine[@]}"})
  if [ ${#tests[@]} -eq 0 ]; then
    printf '==> shard %s has no test files; nothing to do\n' "$SHARD"
    exit 0
  fi
fi

# The combined entry point imports every file above and runs them as groups in
# one process, so the shard split and the file filter have nothing to act on:
# taking either silently would run far more than was asked for.
COMBINED="${VELORKI_ITEST_COMBINED:-}"
COMBINED_ENTRY=integration_test/all_tests.dart
covered=("${tests[@]}")
if [ -n "$COMBINED" ]; then
  if [ -n "$filter" ] || [ -n "$SHARD" ]; then
    printf 'VELORKI_ITEST_COMBINED runs the whole suite: no filter, no shard\n' >&2
    exit 2
  fi
  if [ ! -e "$COMBINED_ENTRY" ]; then
    printf '%s is missing\n' "$COMBINED_ENTRY" >&2
    exit 2
  fi
  tests=("$COMBINED_ENTRY")
fi

if [ -n "${VELORKI_ITEST_DRY_RUN:-}" ]; then
  if [ -n "$COMBINED" ]; then
    printf '==> one combined run of %s, covering %d file(s):\n' \
      "$COMBINED_ENTRY" "${#covered[@]}"
  else
    printf '==> shard %s would run %d file(s):\n' "${SHARD:-1/1}" "${#tests[@]}"
  fi
  printf '%s\n' "${covered[@]}"
  exit 0
fi

if [ -n "$COMBINED" ]; then
  printf '==> %s, %d file(s) in one run, on %s, region %s, segments %s\n' \
    "$COMBINED_ENTRY" "${#covered[@]}" "$DEVICE" "$REGION" "$SEGMENTS_URL"
else
  printf '==> %d test(s) (shard %s) on %s, region %s, segments %s\n' \
    "${#tests[@]}" "${SHARD:-1/1}" "$DEVICE" "$REGION" "$SEGMENTS_URL"
fi
for f in ${skipped[@]+"${skipped[@]}"}; do
  printf '    skipping %s: it needs a BRouter server in VELORKI_BROUTER_URL\n' "$f"
done
printf '\n'

started=$(date +%s)
# How long one `flutter test` invocation may take, in seconds. The longest
# flow (the loop search) finishes in a few minutes; a run that goes beyond
# this is the tooling hanging while it attaches to the app, which happened on
# the iOS simulator, and is retried once like the other tooling failures. A
# combined run is the whole suite in one invocation and needs far more than
# the default, which is why the iOS workflow sets VELORKI_ITEST_TIMEOUT.
LIMIT="${VELORKI_ITEST_TIMEOUT:-900}"

# How long the tooling may take, after the build, to install the app, attach
# and start the first test, in seconds. That takes seconds; on a busy API 35
# emulator the tooling has been seen to wait forever for the app's VM service
# line (flutter_tools has no timeout there), with nothing in the log and
# nothing on the mirror. That used to cost the whole LIMIT before the retry;
# now it costs this. Counted from the build's own "done" line, because an
# Xcode build on a shared macOS runner can take longer than this by itself.
STARTUP="${VELORKI_ITEST_STARTUP_TIMEOUT:-180}"

# The Flutter tooling occasionally fails to bring up its Dart Development
# Service on a busy CI emulator, or to load the file at all, before the app
# has even started; that is retried once, anything the test itself says
# stands.
flutter_test_one() {
  # A previous file's app instance still running on the simulator has been
  # seen to stall the next attach; on Android the tooling restarts it itself.
  if command -v xcrun >/dev/null 2>&1 && [[ "$DEVICE" != emulator-* ]]; then
    xcrun simctl terminate "$DEVICE" com.orkitec.velorki >/dev/null 2>&1 || true
  fi
  flutter test "$1" \
    -d "$DEVICE" \
    --dart-define=VELORKI_BROUTER_URL="$BROUTER_URL" \
    --dart-define=VELORKI_API_URL= \
    --dart-define=VELORKI_SEGMENTS_URL="$SEGMENTS_URL" \
    --dart-define=VELORKI_ITEST_REGION="$REGION" > "$2" 2>&1 &
  local pid=$!
  # Watched from here rather than by a detached sleeper: the launcher turns
  # a kill into a plain exit 1 ("No tests ran."), so the outcome is decided
  # by this loop and a hang is reported as 143.
  local start now passed_at="" built_at="" running_at="" outcome=""
  start=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    sleep 5
    now=$(date +%s)
    # The build's own last line starts the attach window; the reporter's
    # first "+0: <test name>" line ends it ("+0: loading" comes earlier and
    # does not count: the app is not attached yet).
    if [ -z "$built_at" ] && grep -qE '^✓ Built |Xcode build done' "$2"; then
      built_at=$now
    fi
    # The reporter separates its progress lines with carriage returns on
    # macOS, so they are split on both before looking for the first test.
    if [ -z "$running_at" ] && tr '\r' '\n' < "$2" \
      | grep -E '^[0-9]+:[0-9]+ \+[0-9]+: ' | grep -qv ': loading '; then
      running_at=$now
    fi
    if [ -z "$running_at" ] && [ -n "$built_at" ] \
      && [ $((now - built_at)) -ge "$STARTUP" ]; then
      outcome=hung; kill "$pid" 2>/dev/null; break
    fi
    # On the iOS simulator the tooling has been seen to sit for good after
    # the test itself reported its verdict; a verdict that is followed by
    # nothing for half a minute is taken as final.
    if [ -z "$passed_at" ] && grep -q "All tests passed!" "$2"; then
      passed_at=$now
    fi
    if [ -n "$passed_at" ] && [ $((now - passed_at)) -ge 30 ]; then
      outcome=passed; kill "$pid" 2>/dev/null; break
    fi
    if [ $((now - start)) -ge "$LIMIT" ]; then
      outcome=hung; kill "$pid" 2>/dev/null; break
    fi
  done
  local rc=0
  wait "$pid" || rc=$?
  case "$outcome" in
    passed) rc=0 ;;
    hung) rc=143 ;;
  esac
  return "$rc"
}

# Runs one file with its output streamed and kept in a log for the checks.
attempt() {
  local f=$1 log=$2 rc=0
  : > "$log"
  tail -n +1 -f "$log" &
  local reader=$!
  flutter_test_one "$f" "$log" || rc=$?
  sleep 1
  kill "$reader" 2>/dev/null || true
  wait "$reader" 2>/dev/null || true
  return "$rc"
}

# A tooling failure: the watchdog killed a hang (143), the Dart Development
# Service did not come up, or the file never loaded. None of them says
# anything about the test.
tooling_failed() {
  local rc=$1 log=$2
  [ "$rc" -eq 143 ] && return 0
  grep -qE "Failed to start Dart Development Service|^Failed to load \"|No tests ran|0 tests passed" "$log"
}

# Three tries per file: a freshly booted CI emulator has failed the first file
# twice in a row before the tooling settled. A combined run gets one retry and
# no more — a second one would be a third pass over the whole suite, well past
# the job's own timeout, and the attach it is meant to rescue happens once.
TRIES=3
if [ -n "$COMBINED" ]; then TRIES=2; fi

run_one() {
  local f=$1 log rc=0 try
  log=$(mktemp)
  for ((try = 1; try <= TRIES; try++)); do
    rc=0
    attempt "$f" "$log" || rc=$?
    if [ "$rc" -eq 0 ]; then break; fi
    if [ "$try" -lt "$TRIES" ] && tooling_failed "$rc" "$log"; then
      printf '    the tooling did not get going; running %s again (%s of %s)\n' \
        "$(basename "$f")" "$((try + 1))" "$TRIES"
      continue
    fi
    break
  done
  rm -f "$log"
  return "$rc"
}

for f in "${tests[@]}"; do
  printf '==> %s\n' "$f"
  one=$(date +%s)
  run_one "$f"
  printf '    %s: %ss\n\n' "$(basename "$f")" "$(( $(date +%s) - one ))"
done

printf '==> all green in %ss\n' "$(( $(date +%s) - started ))"
