#!/usr/bin/env bash
# Runs the emulator integration suite under integration_test/.
#
#   tool/itest.sh                       # every test, on emulator-5554
#   tool/itest.sh close_loop            # only the tests whose name matches
#   VELORKI_ITEST_DEVICE=... tool/itest.sh
#
# Each file is a separate `flutter test` run — the integration_test binding
# installs one test build per invocation — and the first failure stops the
# script, because a red test usually means every later one is red too.
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

printf '==> %d test(s) on %s, region %s, segments %s\n' \
  "${#tests[@]}" "$DEVICE" "$REGION" "$SEGMENTS_URL"
for f in ${skipped[@]+"${skipped[@]}"}; do
  printf '    skipping %s: it needs a BRouter server in VELORKI_BROUTER_URL\n' "$f"
done
printf '\n'

started=$(date +%s)
# How long one test file may take, in seconds. The longest flow (the loop
# search) finishes in a few minutes; a run that goes beyond this is the
# tooling hanging while it attaches to the app, which happened on the iOS
# simulator, and is retried once like the other tooling failures.
LIMIT="${VELORKI_ITEST_TIMEOUT:-900}"

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
    --dart-define=VELORKI_ITEST_REGION="$REGION" &
  local pid=$!
  # Detached from our output: a sleeper holding the log pipe open would keep
  # the caller waiting for the whole limit after the test has finished. The
  # launcher turns the kill into a plain exit 1 ("No tests ran."), so the
  # watchdog leaves a mark of its own and a hang is reported as 143.
  local mark
  mark=$(mktemp)
  ( sleep "$LIMIT"; echo hung > "$mark"; kill "$pid" 2>/dev/null ) \
    >/dev/null 2>&1 </dev/null &
  local watchdog=$!
  local rc=0
  wait "$pid" || rc=$?
  pkill -P "$watchdog" 2>/dev/null || true
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  if [ -s "$mark" ]; then rc=143; fi
  rm -f "$mark"
  return "$rc"
}

run_one() {
  local f=$1 log rc=0
  log=$(mktemp)
  flutter_test_one "$f" 2>&1 | tee "$log" || rc=$?
  if [ "$rc" -eq 0 ]; then
    rm -f "$log"
    return 0
  fi
  # 143: the watchdog killed it. A load failure is the tooling, not the test.
  if [ "$rc" -eq 143 ] || grep -qE "Failed to start Dart Development Service|^Failed to load \"" "$log"; then
    rm -f "$log"
    printf '    the tooling did not get going; running %s once more\n' "$(basename "$f")"
    flutter_test_one "$f"
    return
  fi
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
