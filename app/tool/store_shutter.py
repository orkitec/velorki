#!/usr/bin/env python3
"""Takes the store screenshots integration_test/store asks for.

    tool/store_shutter.py <udid> <out-dir>

The test writes `Library/Application Support/itest/shot.txt` in the app's
container, an `id=<token>` line and a `name=<theme>/<locale>/NN-name` line,
and waits. This script polls for that file, photographs the simulator's screen
with `simctl io screenshot` into `<out-dir>/<name>.png`, and writes the token
to `shot.ack` beside the request, which lets the test go on. It runs until it
is killed; tool/store_screenshots.sh starts and stops it around each run.
"""
import os
import re
import subprocess
import sys
import time

BUNDLE = "com.orkitec.velorki"
NAME = re.compile(r"^[a-z]+/[a-z]{2,3}(-[A-Za-z]+)?/[0-9]{2}-[a-z0-9-]+$")


def container(udid: str) -> str | None:
    found = subprocess.run(
        ["xcrun", "simctl", "get_app_container", udid, BUNDLE, "data"],
        capture_output=True,
        text=True,
    )
    return found.stdout.strip() if found.returncode == 0 else None


def request(folder: str) -> dict[str, str] | None:
    try:
        with open(os.path.join(folder, "shot.txt")) as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    return dict(line.split("=", 1) for line in lines if "=" in line)


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    udid, out = sys.argv[1], sys.argv[2]
    last = None
    started = False
    while True:
        home = container(udid)
        if home is None:
            time.sleep(1)
            continue
        folder = os.path.join(home, "Library", "Application Support", "itest")
        fields = request(folder)
        if not started:
            # A request an earlier run left behind is not this run's.
            started = True
            last = (fields or {}).get("id")
        if fields is None:
            time.sleep(0.3)
            continue
        token, name = fields.get("id"), fields.get("name", "")
        if token is None or token == last:
            time.sleep(0.3)
            continue
        if not NAME.match(name):
            print(f"store_shutter: refusing the name {name!r}", file=sys.stderr)
            return 1
        target = os.path.join(out, name + ".png")
        os.makedirs(os.path.dirname(target), exist_ok=True)
        subprocess.run(
            ["xcrun", "simctl", "io", udid, "screenshot", "--type=png", target],
            check=True,
            capture_output=True,
        )
        with open(os.path.join(folder, "shot.ack"), "w") as f:
            f.write(token)
        last = token
        print(f"store_shutter: {target}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
