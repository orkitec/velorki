#!/usr/bin/env python3
"""Ride the iOS simulator's GPS along the test region's route.

    tool/sim_ride.py <udid> <region> [speed_mps]

Two things the simulator needs before integration_test/live_ride_test.dart
can record a real ride:

* the location permission for the app, granted through `simctl privacy`.
  A grant before the app is installed does not survive the install, so this
  waits for the app container to appear (flutter test installs, then
  launches) and grants then; the test meanwhile keeps the app from asking
  on its own and waits for the grant to land;
* a moving location: `simctl location start` walks the simulated position
  between the region's waypoints at `speed` m/s, one fix a second, and keeps
  doing so after this script has returned.

`simctl location clear` stops it; tool/itest.sh does that after the run.
"""
import subprocess
import sys
import time

ROUTES = {
    # integration_test/support/region.dart: start -> via -> end
    "nyc": ["40.8153,-73.9645", "40.7995,-73.9580", "40.7829,-73.9654"],
    "madeira": ["32.650,-16.920", "32.700,-16.850", "32.720,-16.770"],
}
BUNDLE = "com.orkitec.velorki"


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    udid, region = sys.argv[1], sys.argv[2]
    speed = sys.argv[3] if len(sys.argv) > 3 else "6"
    waypoints = ROUTES.get(region)
    if waypoints is None:
        print(f"unknown region {region!r}; one of {sorted(ROUTES)}", file=sys.stderr)
        return 2
    subprocess.run(
        ["xcrun", "simctl", "location", udid, "start", f"--speed={speed}",
         "--interval=1", *waypoints],
        check=True,
    )
    print(f"sim_ride: {region} at {speed} m/s on {udid}", flush=True)
    deadline = time.monotonic() + 1200
    while time.monotonic() < deadline:
        installed = subprocess.run(
            ["xcrun", "simctl", "get_app_container", udid, BUNDLE],
            capture_output=True,
        ).returncode == 0
        if installed:
            for kind in ("location-always", "location"):
                subprocess.run(
                    ["xcrun", "simctl", "privacy", udid, "grant", kind, BUNDLE],
                    check=True,
                )
            print("sim_ride: location permission granted", flush=True)
            return 0
        time.sleep(1)
    print("sim_ride: the app never got installed", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
