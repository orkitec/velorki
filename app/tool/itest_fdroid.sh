#!/usr/bin/env bash
# The emulator suite on the Google-free flavour, as the integration workflow
# runs it.
#
#   VELORKI_ITEST_SHARD=1/3 bash tool/itest_fdroid.sh
#
# Expects tool/fdroid_strip.sh to have run already — the whole point is to
# exercise the stripped build — and an emulator the workflow has booted from
# an AOSP (`default`) system image, which has no Google Play Services on it.
# Madeira as the position and the region, because that is the frozen oracle
# tile the mirror on the runner serves. Kept in a file so the workflow's retry
# after a failed boot runs exactly the same, as tool/itest_ci.sh is.
#
# VELORKI_ITEST_FDROID=1 is what makes tool/itest.sh skip the files that
# import a plugin the strip took out, and put the smoke test at the head of
# shard 1.
set -euo pipefail
cd "$(dirname "$0")/.."
adb wait-for-device
adb emu geo fix -16.92 32.65
adb shell settings put secure location_mode 3
VELORKI_ITEST_FDROID=1 \
  VELORKI_ITEST_REGION=madeira \
  VELORKI_ITEST_GEO="-16.92 32.65" \
  VELORKI_SEGMENTS_URL=http://10.0.2.2:8000 \
  tool/itest.sh
