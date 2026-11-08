#!/usr/bin/env bash
# Grants the app the location permission on an emulator while one test file
# runs.
#
#   tool/grant_location.sh emulator-5554 &
#
# The Android half of what tool/sim_ride.py does on the iOS simulator, and for
# the same reason: a test that wants a real fix cannot tap the system dialog,
# and a grant made before an install does not survive it. `flutter test`
# installs more than once on a fresh emulator, so a single grant can land
# before the last install and be gone again. This grants every two seconds
# whenever the app is installed, until tool/itest.sh kills it at the end of
# the file (it starts it for integration_test/fdroid_smoke_test.dart alone),
# or after ten minutes.
set -uo pipefail

DEVICE=${1:?usage: grant_location.sh <device>}
PKG=com.orkitec.velorki

for _ in $(seq 1 300); do
  if adb -s "$DEVICE" shell pm list packages 2>/dev/null | grep -q "^package:$PKG$"; then
    for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION; do
      adb -s "$DEVICE" shell pm grant "$PKG" "android.permission.$p" \
        >/dev/null 2>&1 || true
    done
  fi
  sleep 2
done
exit 0
