#!/usr/bin/env python3
"""Takes the store screenshots integration_test/store asks for.

    tool/store_shutter.py <udid> <out-dir>
    tool/store_shutter.py --android <adb-serial> <out-dir>
    tool/store_shutter.py --android-status-bar <adb-serial>   # set the bar once

The test writes `Library/Application Support/itest/shot.txt` in the app's
container: an `id=<token>` line, a `name=<theme>/<locale>/<screen>` line and an
`action=` line, and waits.

* `action=shot` photographs the simulator's screen with `simctl io
  screenshot` into `<out-dir>/<name>.png`; with `status=offline` the status
  bar shows no signal for that one picture.
* `action=data` copies `data.json` from beside the request to
  `<out-dir>/<name>.json`.
* `action=record-start` starts `simctl io recordVideo` into
  `<out-dir>/<name>.mp4` and answers once the recorder says it is recording;
  `action=record-stop` stops it and answers once the file is complete.

Then the token goes into `shot.ack` beside the request, which lets the test
go on.

With --android the same handshake runs on an Android emulator: the request
lies in the app's `files/itest/` (what getApplicationSupportDirectory is
there), read and answered through `adb shell run-as`, the picture comes from
`adb exec-out screencap`, and the status bar is SystemUI's demo mode, set
and checked before every picture. There is no recording on Android.

The script runs until it is killed; tool/store_screenshots.sh starts and
stops it around each run.
"""
import os
import re
import shutil
import signal
import subprocess
import sys
import time

BUNDLE = "com.orkitec.velorki"
NAME = re.compile(r"^[a-z]+/[a-z]{2,3}(-[A-Za-z]+)?/[a-z0-9-]+$")
# What tool/store_screenshots.sh sets after booting, and the same with no
# signal. A change is always made from a cleared bar with every value given:
# overriding a few of them after "searching" leaves the icons in disorder.
BASE = ["--time", "9:41", "--operatorName", "", "--batteryState", "discharging",
        "--batteryLevel", "100"]
ONLINE = BASE + ["--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
                 "--cellularMode", "active", "--cellularBars", "4"]
OFFLINE = BASE + ["--dataNetwork", "hide", "--wifiMode", "failed", "--wifiBars", "0",
                  "--cellularMode", "active", "--cellularBars", "0"]


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
    subprocess.run(["xcrun", "simctl", "status_bar", udid, "clear"],
                   check=True, capture_output=True)
    # The cleared bar animates to the real state first; an override sent
    # while it does now and then leaves the icons out of order (the battery
    # before the bars, no wifi) for the rest of the run.
    time.sleep(2.5)
    subprocess.run(["xcrun", "simctl", "status_bar", udid, "override", *network],
                   check=True, capture_output=True)
    # The status bar animates the change; a picture taken sooner catches
    # the icons half way.
    time.sleep(2.5)


def start_recording(udid: str, target: str) -> subprocess.Popen:
    recorder = subprocess.Popen(
        ["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", target],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    # simctl says so on its output once the first frame is being written.
    for line in recorder.stdout:
        if "Recording started" in line:
            return recorder
    raise RuntimeError(f"the recorder quit before it started: {target}")


def stop_recording(recorder: subprocess.Popen) -> None:
    recorder.send_signal(signal.SIGINT)
    recorder.wait(timeout=60)


class Android:
    """The handshake and the pictures on an Android emulator, through adb."""

    FOLDER = "files/itest"

    def __init__(self, serial: str):
        self.serial = serial

    def adb(self, *args: str, check: bool = False) -> subprocess.CompletedProcess:
        return subprocess.run(["adb", "-s", self.serial, *args], capture_output=True,
                              check=check)

    def read(self, name: str) -> bytes | None:
        found = self.adb("exec-out", "run-as", BUNDLE, "cat", f"{self.FOLDER}/{name}")
        # run-as says what went wrong on stdout, with status 0 on some images.
        if found.returncode != 0 or found.stdout.startswith(b"run-as:") \
                or found.stdout.startswith(b"cat:"):
            return None
        return found.stdout

    def request(self) -> dict[str, str] | None:
        text = self.read("shot.txt")
        if text is None:
            return None
        lines = text.decode("utf-8", "replace").splitlines()
        return dict(line.split("=", 1) for line in lines if "=" in line)

    def ack(self, token: str) -> None:
        # The token is the test's microsecond clock: digits only.
        if not token.isdigit():
            raise ValueError(f"unexpected token {token!r}")
        self.adb("shell", f"run-as {BUNDLE} sh -c 'echo {token} > {self.FOLDER}/shot.ack'",
                 check=True)

    def status_bar(self, online: bool) -> None:
        android_status_bar(self.serial, online)

    def screenshot(self, target: str) -> None:
        png = self.adb("exec-out", "screencap", "-p", check=True).stdout
        with open(target, "wb") as f:
            f.write(png)


def android_status_bar(serial: str, online: bool) -> None:
    """SystemUI's demo mode: 9:41, a full battery, no notification icons, and
    full wifi, or no network at all when not [online]. No mobile icon: on the
    images tried (API 35) the demo's mobile icon keeps a stale "3G", misses
    the bar's tint and ignores a change of level.

    Set from a fresh demo mode with every value given, before every picture,
    and checked with dumpsys: on a CI emulator the demo mode set after boot
    was gone by the first picture (SystemUI not yet listening, or restarted),
    and the bar showed the real clock and notifications."""
    def adb(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(["adb", "-s", serial, "shell", *args],
                              capture_output=True, text=True)

    def demo(command: str, *extras: str) -> None:
        adb("am", "broadcast", "-a", "com.android.systemui.demo", "-e", "command",
            command, *extras)

    def in_demo_mode() -> bool:
        state = adb("dumpsys", "activity", "service", "com.android.systemui").stdout
        return "isInDemoMode=true" in state

    for attempt in range(1, 6):
        adb("settings", "put", "global", "sysui_demo_allowed", "1")
        demo("exit")
        demo("enter")
        demo("clock", "-e", "hhmm", "0941")
        demo("battery", "-e", "level", "100", "-e", "plugged", "false")
        demo("notifications", "-e", "visible", "false")
        demo("network", "-e", "mobile", "hide")
        if online:
            demo("network", "-e", "wifi", "show", "-e", "level", "4", "-e", "fully", "true")
        else:
            demo("network", "-e", "wifi", "hide")
        # The bar animates the change; a picture taken sooner catches the
        # icons half way.
        time.sleep(2.5)
        if in_demo_mode():
            return
        print(f"store_shutter: demo mode not in effect on {serial} (try {attempt})",
              file=sys.stderr, flush=True)
        time.sleep(3)
    raise RuntimeError(f"SystemUI on {serial} never entered demo mode")


def main_android(serial: str, out: str) -> int:
    device = Android(serial)
    last = None
    started = False
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    while True:
        fields = device.request()
        if not started:
            # A request an earlier run left behind is not this run's.
            started = True
            last = (fields or {}).get("id")
        token, name = (fields or {}).get("id"), (fields or {}).get("name", "")
        if token is None or token == last:
            time.sleep(0.3)
            continue
        if not NAME.match(name):
            print(f"store_shutter: refusing the name {name!r}", file=sys.stderr)
            return 1
        target = os.path.join(out, name)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        action = fields.get("action")
        if action == "data":
            data = device.read("data.json")
            if data is not None:
                with open(target + ".json", "wb") as f:
                    f.write(data)
            print(f"store_shutter: {target}.json", flush=True)
        elif action in ("record-start", "record-stop"):
            print(f"store_shutter: no recording on Android, skipping {name}", file=sys.stderr)
        else:
            device.status_bar(online=fields.get("status") != "offline")
            device.screenshot(target + ".png")
            print(f"store_shutter: {target}.png", flush=True)
        device.ack(token)
        last = token


def main() -> int:
    if len(sys.argv) == 4 and sys.argv[1] == "--android":
        return main_android(sys.argv[2], sys.argv[3])
    if len(sys.argv) == 3 and sys.argv[1] == "--android-status-bar":
        android_status_bar(sys.argv[2], online=True)
        return 0
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    udid, out = sys.argv[1], sys.argv[2]
    last = None
    started = False
    recorder = None

    def quit_(*_):
        # A recording left running would keep the simulator busy for good.
        if recorder is not None and recorder.poll() is None:
            stop_recording(recorder)
        sys.exit(0)

    signal.signal(signal.SIGTERM, quit_)
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
        action = fields.get("action")
        if action == "record-start":
            if recorder is not None:
                stop_recording(recorder)
            recorder = start_recording(udid, target + ".mp4")
            print(f"store_shutter: recording {target}.mp4", flush=True)
        elif action == "record-stop":
            if recorder is not None:
                stop_recording(recorder)
                recorder = None
            print(f"store_shutter: {target}.mp4", flush=True)
        elif action == "data":
            shutil.copyfile(os.path.join(folder, "data.json"), target + ".json")
            print(f"store_shutter: {target}.json", flush=True)
        else:
            offline = fields.get("status") == "offline"
            # Every picture from a bar set afresh: once a ride has run, iOS
            # now and then keeps the icons out of order (the battery before
            # the bars, no wifi) for the rest of the run.
            status_bar(udid, OFFLINE if offline else ONLINE)
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
