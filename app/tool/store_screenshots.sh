#!/usr/bin/env bash
# The App Store screenshots, from the app on the iOS simulator to the finished
# slides.
#
#   tool/store_screenshots.sh                          # en and de, light and dark
#   tool/store_screenshots.sh --locales de --themes dark
#   tool/store_screenshots.sh --skip-capture           # slides from the last capture
#   tool/store_screenshots.sh --shots dark             # both slide styles show the dark app
#   tool/store_screenshots.sh --until variants         # capture only up to that screen
#   tool/store_screenshots.sh --preview                # the preview video instead (store/preview_set.json)
#
# Output, under app/build/store_screenshots/ (git-ignored):
#   raw/<theme>/<locale>/<screen>.png          the simulator's screen, 1320x2868
#   slides/<style>/<size>/<locale>/<slide>.png every slide in both styles
#   slides/set/<size>/<locale>/NN-<slide>.png  the set to upload (store/slide_set.json)
#   slides/set/contact-<locale>.png            the set at a glance
#
# The watch slide's screenshot is taken by tool/store_watch.sh with the
# figures the phone showed, into watch/<theme>/<locale>/riding.png.
#
# What it does:
# * picks the simulator named "Velorki Shots 6.9" (VELORKI_STORE_SIM takes a
#   UDID instead) and creates it as an iPhone 17 Pro Max on the newest iOS
#   runtime when there is none: 1320x2868 is the size App Store Connect wants
#   for 6.9";
# * serves the Madeira tile and its gazetteer with tool/itest_mirror.sh, unless
#   a mirror already answers on the port, and stops it again at the end;
# * per locale, sets the simulator's language and region (the region decides
#   the clock format, in the app and in the status bar) and reboots it, sets
#   the status bar to 9:41 with full bars, and runs
#   integration_test/store/store_screenshots_test.dart once, which takes every
#   theme asked for; tool/store_shutter.py takes the pictures it asks for;
# * tool/store_watch.sh shoots the watch app with the figures the phone
#   showed, on the watch simulator;
# * then tool/store_slides.py makes the slides.
#
# The run clears the library on that simulator; it is meant to be one kept for
# this. Needs Xcode, mise (Flutter), python3 and Google Chrome; the map style
# and its tiles come from the network.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$PWD"
ROOT="$(cd .. && pwd)"
OUT="$APP/build/store_screenshots"
SIM_NAME="Velorki Shots 6.9"
PORT="${VELORKI_STORE_MIRROR_PORT:-8000}"

LOCALES=en,de
THEMES=light,dark
SHOTS=same
CAPTURE=1
UNTIL=
PREVIEW=0
while [ $# -gt 0 ]; do
  case "$1" in
    --locales) LOCALES="$2"; shift ;;
    --themes) THEMES="$2"; shift ;;
    --shots) SHOTS="$2"; shift ;;
    --skip-capture) CAPTURE=0 ;;
    --until) UNTIL="$2"; shift ;;
    --preview) PREVIEW=1 ;;
    -h | --help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//;$d'; exit 0 ;;
    *) printf 'unknown argument %q\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '==> %s\n' "$*"; }
die() { printf 'store_screenshots: %s\n' "$*" >&2; exit 1; }

# The App Store's region for each language the app ships.
region_of() {
  case "$1" in
    en) echo en_US ;;
    de) echo de_DE ;;
    fr) echo fr_FR ;;
    es) echo es_ES ;;
    it) echo it_IT ;;
    nl) echo nl_NL ;;
    *) echo "$1" ;;
  esac
}

simulator() {
  if [ -n "${VELORKI_STORE_SIM:-}" ]; then echo "$VELORKI_STORE_SIM"; return; fi
  local udid
  udid="$(xcrun simctl list devices -j | python3 -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["name"] == name and d.get("isAvailable", True):
            print(d["udid"]); sys.exit()
' "$SIM_NAME")"
  if [ -z "$udid" ]; then
    local runtime
    runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
ios = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print(max(ios, key=lambda r: [int(p) for p in r["version"].split(".")])["identifier"] if ios else "")
')"
    [ -n "$runtime" ] || die "no iOS simulator runtime is installed (xcodebuild -downloadPlatform iOS)"
    udid="$(xcrun simctl create "$SIM_NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max "$runtime")"
    say "created $SIM_NAME ($udid) on $runtime" >&2
  fi
  echo "$udid"
}

boot() {  # boot <udid> <language> <region>
  local udid=$1 language=$2 region=$3
  xcrun simctl boot "$udid" 2> /dev/null || true
  xcrun simctl bootstatus "$udid" -b > /dev/null
  local current
  current="$(xcrun simctl spawn "$udid" defaults read -g AppleLocale 2> /dev/null || true)"
  if [ "$current" != "$region" ]; then
    say "switching the simulator to $language / $region"
    xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array "$language"
    xcrun simctl spawn "$udid" defaults write -g AppleLocale -string "$region"
    xcrun simctl shutdown "$udid"
    xcrun simctl boot "$udid"
    xcrun simctl bootstatus "$udid" -b > /dev/null
  fi
  # A moment for SpringBoard to settle before anything is installed.
  sleep 15
  xcrun simctl status_bar "$udid" override --time 9:41 \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --operatorName '' \
    --batteryState discharging --batteryLevel 100
}

# Runs the test for one locale. Right after the simulator boots, flutter test
# now and then installs and launches the app and then never attaches to it,
# with the app on its splash screen for good; a run that has not started its
# first test within ten minutes is stopped and tried once more.
capture() {
  local locale=$1 log="$WORK/test-$1.log" attempt pid started
  local test=store_screenshots_test.dart first='store screenshots, '
  if [ "$PREVIEW" = 1 ]; then test=store_preview_test.dart first='store preview, '; fi
  for attempt in 1 2; do
    flutter test "integration_test/store/$test" -d "$UDID" \
      --dart-define-from-file="$DEFINES" \
      --dart-define=VELORKI_STORE_LOCALE="$locale" \
      --dart-define=VELORKI_STORE_THEMES="$THEMES" \
      --dart-define=VELORKI_STORE_UNTIL="$UNTIL" \
      --dart-define=VELORKI_PREVIEW_SET="$PREVIEW_SET" > "$log" 2>&1 &
    pid=$!
    started=0
    for _ in $(seq 1 600); do
      kill -0 "$pid" 2> /dev/null || break
      if [ "$started" = 0 ] && grep -q "$first" "$log"; then started=1; fi
      [ "$started" = 1 ] && break
      sleep 1
    done
    if [ "$started" = 1 ] || ! kill -0 "$pid" 2> /dev/null; then
      if wait "$pid"; then
        grep -E 'VELORKI_STORE|All tests passed' "$log" || true
        return 0
      fi
      cat "$log" >&2
      die "the capture for $locale failed"
    fi
    say "the test never started; trying again ($attempt)"
    kill "$pid" 2> /dev/null || true
    wait "$pid" 2> /dev/null || true
  done
  die "the capture for $locale never started"
}

# The theme of each preview clip, as `clip:theme` pairs for the test.
PREVIEW_SET="$(python3 -c '
import json, sys
print(",".join(c["clip"] + ":" + c["theme"] for c in json.load(open(sys.argv[1]))["clips"]))
' "$APP/store/preview_set.json")"

MIRROR_PID=""
SHUTTER_PID=""
WORK="$(mktemp -d)"
cleanup() {
  if [ -n "$SHUTTER_PID" ]; then
    kill "$SHUTTER_PID" 2> /dev/null || true
    wait "$SHUTTER_PID" 2> /dev/null || true
  fi
  [ -n "$MIRROR_PID" ] && kill "$MIRROR_PID" 2> /dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

if [ "$CAPTURE" = 1 ]; then
  command -v xcrun > /dev/null || die "xcrun is missing; this needs Xcode"
  if ! command -v flutter > /dev/null; then
    eval "$(mise env -s bash)" || die "flutter is not on PATH and mise could not provide it"
  fi
  UDID="$(simulator)"
  say "simulator $UDID"

  if curl -sf "http://127.0.0.1:$PORT/manifest.json" > /dev/null; then
    say "a mirror already answers on port $PORT"
  else
    ITEST_MIRROR_PORT="$PORT" bash "$APP/tool/itest_mirror.sh" > /dev/null
    MIRROR_PID="$(cat "$ROOT/mirror.pid")"
    for _ in $(seq 1 20); do
      curl -sf "http://127.0.0.1:$PORT/manifest.json" > /dev/null && break
      sleep 0.5
    done
  fi

  # The committed CI configuration, pointed at the local mirror, with the
  # relay so the planner shows every action it has.
  DEFINES="$WORK/defines.json"
  python3 - "$APP/env/ci.json" "$DEFINES" "$PORT" << 'PY'
import json, sys
defines = json.load(open(sys.argv[1]))
defines.update({
    "VELORKI_SEGMENTS_URL": f"http://127.0.0.1:{sys.argv[3]}",
    "VELORKI_API_URL": "https://api.velorki.com",
    "VELORKI_BROUTER_URL": "",
    "VELORKI_ITEST_REGION": "madeira",
    "VELORKI_STORE_SHOTS": "true",
})
json.dump(defines, open(sys.argv[2], "w"))
PY

  IFS=, read -r -a locales <<< "$LOCALES"
  for locale in "${locales[@]}"; do
    region="$(region_of "$locale")"
    boot "$UDID" "${region/_/-}" "$region"
    python3 "$APP/tool/store_shutter.py" "$UDID" "$OUT/raw" &
    SHUTTER_PID=$!
    if [ "$PREVIEW" = 1 ]; then say "recording $locale"; else say "capturing $locale ($THEMES)"; fi
    capture "$locale"
    kill "$SHUTTER_PID" 2> /dev/null || true
    wait "$SHUTTER_PID" 2> /dev/null || true
    SHUTTER_PID=""
  done

  # The watch takes the figures of the ride, which comes last.
  if [ -z "$UNTIL" ] && [ "$PREVIEW" = 0 ]; then
    say "the watch, with the phone's figures"
    bash "$APP/tool/store_watch.sh" "$OUT/raw" "$OUT/watch" "$LOCALES" "$THEMES"
  fi
fi

if [ "$PREVIEW" = 1 ]; then
  say "making the preview"
  python3 "$APP/tool/store_preview.py" --locales "$LOCALES" \
    --clips "$OUT/raw/preview" --out "$OUT/preview"
  exit 0
fi

say "making the slides"
python3 "$APP/tool/store_slides.py" --locales "$LOCALES" --shots "$SHOTS" \
  --raw "$OUT/raw" --watch "$OUT/watch" --out "$OUT/slides" | tail -1
