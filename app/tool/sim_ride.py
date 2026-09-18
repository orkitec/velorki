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

Once the permission is granted the script stays around and watches the
app's own container for `Library/Application Support/itest/route.txt`, one
`lat,lon` per line: a test writes the route it planned there (see
integration_test/support/sim_gps.dart) and the simulated rider switches to
it. tool/itest.sh kills the script after the run.
"""
import os
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
            return follow_requests(udid, speed, deadline)
        time.sleep(1)
    print("sim_ride: the app never got installed", file=sys.stderr)
    return 1


def follow_requests(udid: str, speed: str, deadline: float) -> int:
    """Rides any route the app writes to its container, until killed."""
    seen = None
    while time.monotonic() < deadline:
        data = subprocess.run(
            ["xcrun", "simctl", "get_app_container", udid, BUNDLE, "data"],
            capture_output=True, text=True,
        )
        if data.returncode == 0:
            path = os.path.join(
                data.stdout.strip(), "Library", "Application Support",
                "itest", "route.txt",
            )
            if os.path.exists(path):
                stamp = os.path.getmtime(path)
                if stamp != seen:
                    seen = stamp
                    with open(path) as fh:
                        points = [line.strip() for line in fh if line.strip()]
                    if len(points) >= 2:
                        subprocess.run(
                            ["xcrun", "simctl", "location", udid, "start",
                             f"--speed={speed}", "--interval=1", *points],
                            check=True,
                        )
                        print(f"sim_ride: riding the app's route, "
                              f"{len(points)} points", flush=True)
        time.sleep(1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
