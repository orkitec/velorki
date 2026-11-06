#!/usr/bin/env bash
# The emulator suite as the integration workflow runs it, on an emulator the
# workflow has booted: Madeira as the position (the frozen oracle tile is
# there) and the tests' region, the mirror on the runner, one shard. Kept in a
# file so the workflow's retry after a failed boot runs exactly the same.
#
#   VELORKI_ITEST_SHARD=1/3 app/tool/itest_ci.sh
set -euo pipefail
cd "$(dirname "$0")/.."
adb wait-for-device
adb emu geo fix -16.92 32.65
adb shell settings put secure location_mode 3
# VELORKI_ITEST_GEO: the position again, if itest.sh restarts the emulator.
VELORKI_ITEST_REGION=madeira \
  VELORKI_ITEST_GEO="-16.92 32.65" \
  VELORKI_SEGMENTS_URL=http://10.0.2.2:8000 \
  tool/itest.sh
