#!/usr/bin/env bash
# Grants the app the location permission on an emulator, the moment
# `flutter test` has installed it.
#
#   tool/grant_location.sh emulator-5554 &
#
# The Android half of what tool/sim_ride.py does on the iOS simulator, and for
# the same reason: a test that wants a real fix cannot tap the system dialog,
# and a grant made before the install does not survive it. So this waits for
# the package to appear and grants then. Started by tool/itest.sh for every
# emulator run; harmless for the tests that fake the position source, which is
# all of them but integration_test/fdroid_smoke_test.dart.
#
# Exits once the grant is in, or after about two minutes.
set -uo pipefail

DEVICE=${1:?usage: grant_location.sh <device>}
PKG=com.orkitec.velorki

for _ in $(seq 1 240); do
  if adb -s "$DEVICE" shell pm list packages 2>/dev/null | grep -q "^package:$PKG$"; then
    for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION; do
      adb -s "$DEVICE" shell pm grant "$PKG" "android.permission.$p" \
        >/dev/null 2>&1 || true
    done
    # A fresh install revokes them again, so this keeps going for a moment in
    # case the install was still running when the grant landed.
    sleep 5
    for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION; do
      adb -s "$DEVICE" shell pm grant "$PKG" "android.permission.$p" \
        >/dev/null 2>&1 || true
    done
    exit 0
  fi
  sleep 0.5
done
exit 0
