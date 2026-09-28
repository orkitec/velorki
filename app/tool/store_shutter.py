#!/usr/bin/env python3
"""Takes the store screenshots integration_test/store asks for.

    tool/store_shutter.py <udid> <out-dir>

The test writes `Library/Application Support/itest/shot.txt` in the app's
container: an `id=<token>` line, a `name=<theme>/<locale>/<screen>` line and an
`action=` line, and waits.

* `action=shot` photographs the simulator's screen with `simctl io
  screenshot` into `<out-dir>/<name>.png`; with `status=offline` the status
  bar shows no signal for that one picture.
* `action=data` copies `data.json` from beside the request to
  `<out-dir>/<name>.json`.

Then the token goes into `shot.ack` beside the request, which lets the test
go on. The script runs until it is killed; tool/store_screenshots.sh starts
and stops it around each run.
"""
import os
import re
import shutil
import subprocess
import sys
import time

BUNDLE = "com.orkitec.velorki"
NAME = re.compile(r"^[a-z]+/[a-z]{2,3}(-[A-Za-z]+)?/[a-z0-9-]+$")
ONLINE = ["--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
          "--cellularMode", "active", "--cellularBars", "4"]
OFFLINE = ["--dataNetwork", "hide", "--wifiMode", "failed", "--wifiBars", "0",
           "--cellularMode", "searching", "--cellularBars", "0"]


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


def status_bar(udid: str, network: list[str]) -> None:
    subprocess.run(["xcrun", "simctl", "status_bar", udid, "override", *network],
                   check=True, capture_output=True)
    time.sleep(0.5)


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
        target = os.path.join(out, name)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if fields.get("action") == "data":
            shutil.copyfile(os.path.join(folder, "data.json"), target + ".json")
            print(f"store_shutter: {target}.json", flush=True)
        else:
            offline = fields.get("status") == "offline"
            if offline:
                status_bar(udid, OFFLINE)
            try:
                subprocess.run(
                    ["xcrun", "simctl", "io", udid, "screenshot", "--type=png",
                     target + ".png"],
                    check=True,
                    capture_output=True,
                )
            finally:
                if offline:
                    status_bar(udid, ONLINE)
            print(f"store_shutter: {target}.png", flush=True)
        with open(os.path.join(folder, "shot.ack"), "w") as f:
            f.write(token)
        last = token


if __name__ == "__main__":
    sys.exit(main())
