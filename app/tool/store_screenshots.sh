#!/usr/bin/env bash
# The App Store screenshots, from the app on the iOS simulator to the finished
# slides; with --platform ipad, the 13" iPad ones; with --platform duo, the
# iPhone Duo's (its inner display); with --platform android, the Google Play
# ones from an Android emulator.
#
#   tool/store_screenshots.sh                          # every language, light and dark
#   tool/store_screenshots.sh --locales de --themes dark
#   tool/store_screenshots.sh --skip-capture           # slides from the last capture
#   tool/store_screenshots.sh --shots dark             # both slide styles show the dark app
#   tool/store_screenshots.sh --until variants         # capture only up to that screen
#   tool/store_screenshots.sh --all-shots              # every screen in every theme
#   tool/store_screenshots.sh --no-slides              # the pictures (and the watch) only
#   tool/store_screenshots.sh --watch-locales en,de    # the watch in these languages ('none': not at all)
#   tool/store_screenshots.sh --preview                # the preview video instead (store/preview_set.json)
#   tool/store_screenshots.sh --platform ipad          # the iPad set; see below
#   tool/store_screenshots.sh --platform duo           # the iPhone Duo set; see below
#   tool/store_screenshots.sh --platform android       # the Google Play set; see below
#   tool/store_screenshots.sh --platform android-tablet  # Google Play's tablet set; see below
#
# Output, under app/build/store_screenshots/ (git-ignored):
#   raw/<theme>/<locale>/<screen>.png          the simulator's screen, 1320x2868
#   slides/<style>/<size>/<locale>/<slide>.png every slide in both styles
#   slides/set/<size>/<locale>/NN-<slide>.png  the set to upload (store/slide_set.json)
#   slides/set/contact-<locale>.png            the set at a glance
#
# The watch slide's screenshot is taken by tool/store_watch.sh with the
# figures the phone showed, into watch/<theme>/<locale>/riding.png, and the
# App Store's four watch screenshots beside it in store/.
#
# What it does:
# * picks the simulator named "Velorki Shots 6.9" (VELORKI_STORE_SIM takes a
#   UDID instead) and creates it as an iPhone 17 Pro Max on the newest iOS
#   runtime when there is none: 1320x2868 is the size App Store Connect wants
#   for 6.9";
# * serves the Madeira tile and its gazetteer with tool/itest_mirror.sh, unless
#   a mirror already answers on the port, and stops it again at the end; beside
#   them New York's W75_N40 tile and gazetteer for the cycle map shots, fetched
#   once from the tile mirror into VELORKI_STORE_TILES (~/.cache/velorki-tiles/store);
# * sets the simulator's language and region and reboots it if they differ,
#   sets the status bar to 9:41 with full bars, and runs
#   integration_test/store/store_screenshots_test.dart, which takes every
#   screen in every language and theme of the run, switching them in the
#   app: on iOS once for English and once for the other languages, whose
#   region shows the status bar's clock another way (see below); on Android
#   once. tool/store_shutter.py takes the pictures it asks for. The preview
#   is recorded once per language, the device set to each;
# * tool/store_watch.sh shoots the watch app with the figures the phone
#   showed, on the watch simulator;
# * then tool/store_slides.py makes the slides.
#
# --platform ipad takes the same screens on the simulator "Velorki Shots iPad
# 13" (VELORKI_STORE_SIM again takes a UDID), created as an iPad Pro 13-inch
# (M5), with the screen locked sideways by the test (VELORKI_STORE_ORIENTATION):
# 2752x2064, a size App Store Connect takes for 13". The slides are those of
# store/slide_set_ipad.json; no watch or preview. Output under
# ipad/: raw/<theme>/<locale>/<screen>.png and slides/ (see
# tool/store_slides.py --platform ipad).
#
# --platform duo takes the same screens on the simulator "Velorki Shots Duo"
# (VELORKI_STORE_SIM again takes a UDID), created as an iPhone Duo on the
# newest iOS runtime that has one (27.1 or later). It boots folded: after
# every boot tool/duo_state.c, built for the simulator and run in it, opens
# the hinge to 180 degrees and holds the device upright, which lays the inner
# display on its side, and the pictures are of that display, 2853x2007 (the
# port of `simctl io enumerate` that is 2007x2853). The slides are the iPad's
# set; no watch or preview. Output under duo/. Never `simctl io <duo>
# screenConfig`: it crash-loops SpringBoard.
#
# --platform android takes the screens the Play set uses (store/
# slide_set_android.json) on an Android emulator: VELORKI_STORE_EMULATOR names
# its adb serial, else the one emulator running is taken (start one first: a
# Pixel 6 profile, 1080x2400). Per locale the emulator's language is set (adb
# root, a reboot when it changes), gestural navigation and a hole-punch cutout
# are switched on, and SystemUI's demo mode shows 9:41 and full wifi; the
# mirror is reached as 10.0.2.2. No watch, Lock Screen or preview. Output
# under android/: raw/<theme>/<locale>/<screen>.png and slides/ (see
# tool/store_slides.py --platform android).
#
# --platform android-tablet does the same on a tablet emulator (a Pixel
# Tablet profile, 2560x1600 landscape, where the app takes its wide layout),
# without the phone's hole-punch, for the slides of store/slide_set_ipad.json.
# Output under android-tablet/.
#
# VELORKI_STORE_MONITOR=<seconds> logs memory, disk, the busiest processes and
# the booted simulators that often (the workflow sets it).
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
SIM_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max
PORT="${VELORKI_STORE_MIRROR_PORT:-8000}"

LOCALES=en,de,fr,es,it,nl
THEMES=light,dark
SHOTS=same
CAPTURE=1
UNTIL=
ALL_SHOTS=0
SLIDES=1
WATCH_LOCALES=
PREVIEW=0
PLATFORM=ios
ORIENTATION=
while [ $# -gt 0 ]; do
  case "$1" in
    --locales) LOCALES="$2"; shift ;;
    --themes) THEMES="$2"; shift ;;
    --shots) SHOTS="$2"; shift ;;
    --skip-capture) CAPTURE=0 ;;
    --until) UNTIL="$2"; shift ;;
    --all-shots) ALL_SHOTS=1 ;;
    --no-slides) SLIDES=0 ;;
    --watch-locales) WATCH_LOCALES="$2"; shift ;;
    --preview) PREVIEW=1 ;;
    --platform) PLATFORM="$2"; shift ;;
    -h | --help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//;$d'; exit 0 ;;
    *) printf 'unknown argument %q\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '==> %s\n' "$*"; }
die() { printf 'store_screenshots: %s\n' "$*" >&2; exit 1; }

ANDROID=0
case "$PLATFORM" in android*) ANDROID=1 ;; esac
case "$PLATFORM" in
  ios) ;;
  ipad)
    [ "$PREVIEW" = 0 ] || die "the preview is recorded on the iPhone only"
    OUT="$OUT/ipad"
    SIM_NAME="Velorki Shots iPad 13"
    SIM_TYPE=com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB
    ORIENTATION=landscape
    ;;
  duo)
    [ "$PREVIEW" = 0 ] || die "the preview is recorded on the iPhone only"
    OUT="$OUT/duo"
    SIM_NAME="Velorki Shots Duo"
    SIM_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-Duo
    ;;
  android | android-tablet)
    [ "$PREVIEW" = 0 ] || die "the preview is recorded on iOS only"
    OUT="$OUT/$PLATFORM"
    ;;
  *) die "unknown platform $PLATFORM (ios, ipad, duo, android or android-tablet)" ;;
esac

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
    # The newest runtime that has the device: the Duo needs iOS 27.1, and
    # a runner can have only 27.0.
    runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
kind = sys.argv[1]
ios = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]
       and any(d["identifier"] == kind for d in r.get("supportedDeviceTypes", []))]
print(max(ios, key=lambda r: [int(p) for p in r["version"].split(".")])["identifier"] if ios else "")
' "$SIM_TYPE")"
    [ -n "$runtime" ] || die "no installed iOS simulator runtime supports $SIM_TYPE (xcodebuild -downloadPlatform iOS; the iPhone Duo needs iOS 27.1 or later)"
    # Command substitution does not inherit set -e: a failed create would
    # go on with its message as the UDID.
    udid="$(xcrun simctl create "$SIM_NAME" "$SIM_TYPE" "$runtime")" \
      || die "could not create $SIM_NAME ($SIM_TYPE) on $runtime"
    say "created $SIM_NAME ($udid) on $runtime" >&2
  fi
  echo "$udid"
}

shut_down() {  # shut_down <udid>: whether the simulator is shut down
  xcrun simctl list devices -j | python3 -c '
import json, sys
udid = sys.argv[1]
sys.exit(not any(d["udid"] == udid and d["state"] == "Shutdown"
                 for ds in json.load(sys.stdin)["devices"].values() for d in ds))' "$1"
}

write_region() {  # write_region <udid> <language> <region>, the simulator shut down
  local prefs="$HOME/Library/Developer/CoreSimulator/Devices/$1/data/Library/Preferences/.GlobalPreferences.plist"
  mkdir -p "$(dirname "$prefs")"
  [ -f "$prefs" ] || plutil -create binary1 "$prefs"
  plutil -replace AppleLanguages -json "[\"$2\"]" "$prefs"
  plutil -replace AppleLocale -string "$3" "$prefs"
}

boot() {  # boot <udid> <language> <region>
  local udid=$1 language=$2 region=$3
  # Shut down, the simulator's language and region go straight into its
  # preferences, so it boots in them once instead of booting, being told
  # and booting again (minutes on a runner); the check below stays for a
  # simulator already running, or one that ignored the file.
  if shut_down "$udid"; then write_region "$udid" "$language" "$region"; fi
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
  [ "$PLATFORM" = duo ] && unfold "$udid"
  # The iPad held sideways, as the test then locks the screen: the turn the
  # app is asked for is then the one the device is already in.
  if [ "$ORIENTATION" = landscape ]; then
    build_duo_state
    xcrun simctl spawn "$udid" "$DUO_STATE" orientation landscape-left \
      || say "could not turn the simulator; the test turns the screen itself"
  fi
  # A moment for SpringBoard to settle before anything is installed.
  sleep 15
  python3 "$APP/tool/store_shutter.py" --status-bar "$udid"
}

# The iPhone Duo boots folded, on its outer display: opened flat and held
# upright, its inner display is the active one, wider than tall.
DUO_STATE=""
build_duo_state() {
  if [ -z "$DUO_STATE" ]; then
    DUO_STATE="$WORK/duo_state"
    xcrun -sdk iphonesimulator clang -arch "$(uname -m)" -mios-simulator-version-min=17.0 -O2 \
      -o "$DUO_STATE" "$APP/tool/duo_state.c" -framework IOKit -framework CoreFoundation
    codesign -f -s - "$DUO_STATE" 2> /dev/null
  fi
}
unfold() {  # unfold <udid>
  local udid=$1
  build_duo_state
  xcrun simctl spawn "$udid" "$DUO_STATE" hinge 180
  xcrun simctl spawn "$udid" "$DUO_STATE" orientation portrait
  local displays
  for _ in $(seq 1 60); do
    # Read whole first: grep -q would end the pipe early, and devicectl's
    # broken pipe fails it under pipefail.
    displays="$(xcrun devicectl device info displays -d "$udid" 2> /dev/null || true)"
    case "$displays" in *'LCD-1 (active)'*) say "unfolded, the inner display active"; return 0 ;; esac
    sleep 1
  done
  xcrun devicectl device info displays -d "$udid" >&2 || true
  die "the Duo's inner display never became active"
}

# The UUID of the Duo's inner display, the 2007x2853 framebuffer.
inner_display() {  # inner_display <udid>
  xcrun simctl io "$1" enumerate | python3 -c '
import re, sys
for port in sys.stdin.read().split("Port:"):
    uuid = re.search(r"UUID: (\S+)", port)
    if uuid and "Default width: 2007" in port and "Default height: 2853" in port:
        print(uuid.group(1)); break
'
}

# The adb serial of the emulator to use.
emulator_serial() {
  if [ -n "${VELORKI_STORE_EMULATOR:-}" ]; then echo "$VELORKI_STORE_EMULATOR"; return; fi
  local found
  found="$(adb devices | awk '$1 ~ /^emulator-/ && $2 == "device" {print $1}')"
  [ -n "$found" ] || die "no Android emulator is running (or set VELORKI_STORE_EMULATOR)"
  [ "$(printf '%s\n' "$found" | wc -l)" -eq 1 ] \
    || die "more than one emulator is running; set VELORKI_STORE_EMULATOR to one of: $(echo $found)"
  echo "$found"
}

wait_for_boot() {  # wait_for_boot <serial>
  adb -s "$1" wait-for-device
  for _ in $(seq 1 180); do
    [ "$(adb -s "$1" shell getprop sys.boot_completed 2> /dev/null | tr -d '\r')" = 1 ] && return 0
    sleep 1
  done
  die "$1 did not finish booting"
}

android_boot() {  # android_boot <serial> <language-tag>
  local serial=$1 tag=$2 current
  wait_for_boot "$serial"
  current="$(adb -s "$serial" shell getprop persist.sys.locale | tr -d '\r')"
  if [ "$current" != "$tag" ]; then
    say "switching the emulator to $tag"
    if adb -s "$serial" root > /dev/null 2>&1; then
      sleep 2
      wait_for_boot "$serial"
      adb -s "$serial" shell setprop persist.sys.locale "$tag"
      adb -s "$serial" reboot
      sleep 5
      wait_for_boot "$serial"
    else
      say "no adb root on $serial; the status bar keeps the language $current"
    fi
  fi
  # A Pixel's gesture bar and, on the phone, its hole-punch, whatever the
  # image defaults to: both decide where the app's chrome sits. The Pixel
  # Tablet's camera is in its bezel.
  local cutout=com.android.internal.display.cutout.emulation.hole
  if [ "$PLATFORM" = android ]; then
    adb -s "$serial" shell cmd overlay enable-exclusive --category "$cutout" > /dev/null 2>&1 || true
  fi
  adb -s "$serial" shell cmd overlay enable-exclusive --category \
    com.android.internal.systemui.navbar.gestural > /dev/null 2>&1 || true
  # A moment for SystemUI to settle before the bar is set.
  sleep 10
  # Then the cutout off and on again: after a reboot the status bar is now and
  # then laid out for no cutout, its top row cut off, until it changes.
  if [ "$PLATFORM" = android ]; then
    adb -s "$serial" shell cmd overlay disable "$cutout" > /dev/null 2>&1 || true
    sleep 3
    adb -s "$serial" shell cmd overlay enable-exclusive --category "$cutout" > /dev/null 2>&1 || true
    sleep 5
  fi
  adb -s "$serial" shell settings put global sysui_demo_allowed 1
  python3 "$APP/tool/store_shutter.py" --android-status-bar "$serial"
}

# New York's tile and gazetteer, for the cycle map shots: from the snapshot the
# tile mirror points at now, kept in CITY_DIR and fetched again only when that
# snapshot has other bytes.
CITY_TILE=W75_N40
CITY_DIR="${VELORKI_STORE_TILES:-$HOME/.cache/velorki-tiles/store}"
MIRROR_LATEST="${VELORKI_STORE_MIRROR:-https://raw.githubusercontent.com/orkitec/velorki-data/main/latest.json}"
fetch_city_tile() {
  mkdir -p "$CITY_DIR"
  python3 - "$MIRROR_LATEST" "$CITY_TILE" "$CITY_DIR" << 'PY' || die "could not fetch $CITY_TILE"
import hashlib, json, os, subprocess, sys

latest, tile, out = sys.argv[1:]

def curl(url, *args):
    return subprocess.run(
        ["curl", "--retry", "3", "--retry-all-errors", "--fail", "--location",
         "--silent", "--show-error", "--user-agent",
         "velorki-store (+https://github.com/orkitec/velorki)", *args, url],
        check=True, stdout=subprocess.PIPE).stdout

def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()

pointer = json.loads(curl(latest))
bases = [s["baseUrl"] for s in pointer.get("shards", []) if s.get("baseUrl")]
if pointer.get("baseUrl") and pointer["baseUrl"] not in bases:
    bases.insert(0, pointer["baseUrl"])
for base in bases:
    entry = next((t for t in json.loads(curl(base + "manifest.json"))["tiles"]
                  if t["tile"] == tile), None)
    if entry:
        break
else:
    sys.exit(f"{tile} is in no shard of {pointer['tag']}")
files = [(tile + ".rd5", entry["sha256"])]
if entry.get("gazetteer"):
    files.append((tile + ".gaz", entry["gazetteer"]["sha256"]))
for name, want in files:
    path = os.path.join(out, name)
    if os.path.exists(path) and sha256(path) == want:
        continue
    print(f"==> fetching {name} from {pointer['tag']}", file=sys.stderr)
    curl(base + name, "--output", path + ".part")
    if sha256(path + ".part") != want:
        sys.exit(f"{name} does not match the mirror's sha256")
    os.replace(path + ".part", path)
PY
}

# Runs the test: for the screenshots once with every locale, for the preview
# with the one given. Right after the simulator boots, flutter test
# now and then installs and launches the app and then never attaches to it,
# with the app on its splash screen for good; a run that has not started its
# first test within VELORKI_STORE_ATTACH_TIMEOUT seconds (four minutes) of
# the build being done, or within VELORKI_STORE_START_TIMEOUT seconds (ten
# minutes) at all, is stopped and tried once more. The expanded reporter
# names a test when it starts, not when it ends.
capture() {
  local locale=$1 log="$WORK/test-${1//,/-}.log" attempt pid started
  local test=store_screenshots_test.dart first='store screenshots, '
  if [ "$PREVIEW" = 1 ]; then test=store_preview_test.dart first='store preview, '; fi
  for attempt in 1 2; do
    flutter test "integration_test/store/$test" -d "$DEVICE" --reporter expanded \
      ${VELORKI_STORE_VERBOSE:+-v} \
      --dart-define-from-file="$DEFINES" \
      --dart-define=VELORKI_STORE_LOCALE="$locale" \
      --dart-define=VELORKI_STORE_LOCALES="$locale" \
      --dart-define=VELORKI_STORE_THEMES="$THEMES" \
      --dart-define=VELORKI_STORE_UNTIL="$UNTIL" \
      --dart-define=VELORKI_STORE_NEED="$NEED" \
      --dart-define=VELORKI_STORE_LATE_CHECK="${VELORKI_STORE_LATE_CHECK:-false}" \
      --dart-define=VELORKI_STORE_ORIENTATION="$ORIENTATION" \
      --dart-define=VELORKI_PREVIEW_SET="$PREVIEW_SET" > "$log" 2>&1 &
    pid=$!
    started=0 built=""
    for second in $(seq 1 "${VELORKI_STORE_START_TIMEOUT:-600}"); do
      kill -0 "$pid" 2> /dev/null || break
      # The reporter's line for the test (a verbose log also prints the
      # command line, with every VELORKI_STORE define in it).
      if [ "$started" = 0 ] && grep -qE "[0-9]+:[0-9]+ \+[0-9]+.*: $first|VELORKI_STORE (shot|data|recording)" "$log"; then started=1; fi
      [ "$started" = 1 ] && break
      if [ -z "$built" ] && grep -qE 'Xcode build done|Built build/app' "$log"; then built=$second; fi
      if [ -n "$built" ] && [ $((second - built)) -ge "${VELORKI_STORE_ATTACH_TIMEOUT:-240}" ]; then break; fi
      sleep 1
    done
    if [ "$started" = 1 ] || ! kill -0 "$pid" 2> /dev/null; then
      local status=0
      wait "$pid" || status=$?
      # VELORKI_STORE_VERBOSE keeps flutter's whole log (-v), timestamped by
      # the monitor's ticks, under logs/ for the artifact.
      if [ -n "${VELORKI_STORE_VERBOSE:-}" ]; then
        mkdir -p "$OUT/logs"
        cp "$log" "$OUT/logs/test-${locale//,/-}-$attempt.log"
      fi
      if [ "$status" = 0 ]; then
        grep -E 'VELORKI_STORE|All tests passed' "$log" || true
        return 0
      fi
      # On a loaded runner Xcode's build settings query now and then gives
      # up ("No Xcode build settings have been found"), and the app is never
      # built: that is tried once more, like a test that never started.
      if [ "$attempt" = 1 ] && ! grep -q 'VELORKI_STORE' "$log" \
        && grep -qE 'Could not build the application|Unable to start the app on the device' "$log"; then
        say "the app was not built; trying again"
        continue
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
# The screens, each in the themes, the platform's slide set uses (a split
# slide both, and the dark one in its other accent too), with on the iPhone
# those of the App Store's creative assets (tool/store_creative.py) and on
# Android those the website takes from here (tool/screenshots.sh): the test
# shoots only these, as `screen:theme` pairs. --all-shots takes every screen
# in every theme, and the slides in both styles. WATCH_THEME is the theme of
# the watch slide, the only one the watch is shot in.
NEED="" WATCH_THEME=""
if [ "$ALL_SHOTS" = 0 ] && [ "$PREVIEW" = 0 ]; then
  read -r NEED WATCH_THEME < <(python3 "$APP/tool/store_need.py" "$PLATFORM")
  [ "$WATCH_THEME" != "-" ] || WATCH_THEME=""
fi

PREVIEW_SET="$(python3 -c '
import json, sys
print(",".join(c["clip"] + ":" + c["theme"] for c in json.load(open(sys.argv[1]))["clips"]))
' "$APP/store/preview_set.json")"

MIRROR_PID=""
CREATIVE_PID=""
PLIST_BACKUP=""
SHUTTER_PID=""
MONITOR_PID=""
DEMO_SERIAL=""
WORK="$(mktemp -d)"
cleanup() {
  if [ -n "$MONITOR_PID" ]; then
    kill "$MONITOR_PID" 2> /dev/null || true
    wait "$MONITOR_PID" 2> /dev/null || true
  fi
  if [ -n "$SHUTTER_PID" ]; then
    kill "$SHUTTER_PID" 2> /dev/null || true
    wait "$SHUTTER_PID" 2> /dev/null || true
  fi
  [ -n "$MIRROR_PID" ] && kill "$MIRROR_PID" 2> /dev/null || true
  if [ -n "$DEMO_SERIAL" ]; then
    adb -s "$DEMO_SERIAL" shell am broadcast -a com.android.systemui.demo \
      -e command exit > /dev/null 2>&1 || true
  fi
  # The capture build's full-screen flag (below) comes off again.
  if [ -n "$PLIST_BACKUP" ] && [ -f "$PLIST_BACKUP" ]; then
    cp "$PLIST_BACKUP" "$APP/ios/Runner/Info.plist"
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# An iPad app that supports multitasking ignores the orientations a Flutter
# app asks for, so the test could not turn the iPad. The capture build is
# marked full-screen, which makes iPadOS honour them; the Info.plist is put
# back when the script ends.
PLIST_BACKUP=""
if [ "$ORIENTATION" = landscape ]; then
  PLIST_BACKUP="$WORK/Info.plist"
  cp "$APP/ios/Runner/Info.plist" "$PLIST_BACKUP"
  plutil -replace UIRequiresFullScreen -bool YES "$APP/ios/Runner/Info.plist"
fi

# Every VELORKI_STORE_MONITOR seconds (the workflow sets it), what the machine
# is doing: memory, swap, disk, the busiest processes, the booted simulators
# and the test's last line, so a runner that dies mid-capture leaves a trail.
monitor() {
  # Asleep in the background and waited for, so a TERM ends it at once.
  local nap
  trap 'kill "$nap" 2> /dev/null; exit 0' TERM
  while true; do
    sleep "$VELORKI_STORE_MONITOR" &
    nap=$!
    wait "$nap"
    {
      echo "--- $(date -u +%H:%M:%S) monitor"
      memory_pressure -Q 2> /dev/null | tail -1
      echo "swap: $(sysctl -n vm.swapusage 2> /dev/null)"
      df -h / "$HOME" 2> /dev/null | awk 'NR == 1 || !seen[$0]++'
      top -l 2 -s 1 -n 6 -o cpu -stats pid,command,cpu,mem 2> /dev/null | tail -7
      xcrun simctl list devices booted 2> /dev/null | grep -v '^[=-]' || true
      tail -n 1 "$WORK"/test-*.log 2> /dev/null | grep -v '^==>' | cut -c1-200 || true
      echo "---"
    } >&2
  done
}
if [ "${VELORKI_STORE_MONITOR:-0}" -gt 0 ] 2> /dev/null; then
  monitor &
  MONITOR_PID=$!
fi

if [ "$CAPTURE" = 1 ]; then
  if ! command -v flutter > /dev/null; then
    eval "$(mise env -s bash)" || die "flutter is not on PATH and mise could not provide it"
  fi
  if [ "$ANDROID" = 1 ]; then
    # The first SDK that has one; mise.toml names the Linux place.
    for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
      if [ -n "$sdk" ] && [ -x "$sdk/platform-tools/adb" ]; then
        export ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk"
        PATH="$sdk/platform-tools:$PATH"
        break
      fi
    done
    command -v adb > /dev/null || die "adb is missing; this needs the Android SDK's platform-tools"
    DEVICE="$(emulator_serial)"
    say "emulator $DEVICE"
    HOST=10.0.2.2
  else
    command -v xcrun > /dev/null || die "xcrun is missing; this needs Xcode"
    UDID="$(simulator)"
    DEVICE="$UDID"
    say "simulator $UDID"
    HOST=127.0.0.1
  fi

  if curl -sf "http://127.0.0.1:$PORT/manifest.json" > /dev/null; then
    say "a mirror already answers on port $PORT"
    curl -sf "http://127.0.0.1:$PORT/manifest.json" | grep -q "\"$CITY_TILE\"" \
      || die "the mirror on port $PORT has no $CITY_TILE, which the cycle map shots need"
  else
    fetch_city_tile
    ITEST_MIRROR_PORT="$PORT" ITEST_MIRROR_EXTRA="$CITY_DIR/$CITY_TILE.rd5" \
      bash "$APP/tool/itest_mirror.sh" > /dev/null
    MIRROR_PID="$(cat "$ROOT/mirror.pid")"
    for _ in $(seq 1 20); do
      curl -sf "http://127.0.0.1:$PORT/manifest.json" > /dev/null && break
      sleep 0.5
    done
  fi

  # The committed CI configuration, pointed at the local mirror, with the
  # relay so the planner shows every action it has.
  DEFINES="$WORK/defines.json"
  python3 - "$APP/env/ci.json" "$DEFINES" "$PORT" "$HOST" << 'PY'
import json, sys
defines = json.load(open(sys.argv[1]))
defines.update({
    "VELORKI_SEGMENTS_URL": f"http://{sys.argv[4]}:{sys.argv[3]}",
    "VELORKI_API_URL": "https://api.velorki.com",
    "VELORKI_BROUTER_URL": "",
    "VELORKI_ITEST_REGION": "madeira",
    "VELORKI_STORE_SHOTS": "true",
})
json.dump(defines, open(sys.argv[2], "w"))
PY

  # The screenshots in as few runs as the status bar allows, each switching
  # its languages in the app. On iOS the region the simulator booted with
  # decides the status bar's clock and date (9:41 AM Sat Sep 12, or 09:41
  # Sat 12 Sep), and only a reboot changes it: so English runs on its own,
  # the other languages together. On Android the shutter sets the clock per
  # picture, so one run takes them all. The preview runs once per language.
  IFS=, read -r -a locales <<< "$LOCALES"
  if [ "$PREVIEW" = 1 ]; then
    runs=("${locales[@]}")
  elif [ "$ANDROID" = 1 ]; then
    runs=("$LOCALES")
  else
    twelve="" others=""
    for locale in "${locales[@]}"; do
      case "$locale" in
        en*) twelve="${twelve:+$twelve,}$locale" ;;
        *) others="${others:+$others,}$locale" ;;
      esac
    done
    runs=()
    if [ -n "$twelve" ]; then runs+=("$twelve"); fi
    if [ -n "$others" ]; then runs+=("$others"); fi
  fi
  for run in "${runs[@]}"; do
    region="$(region_of "${run%%,*}")"
    if [ "$ANDROID" = 1 ]; then
      android_boot "$DEVICE" "${region/_/-}"
      DEMO_SERIAL="$DEVICE"
      python3 "$APP/tool/store_shutter.py" --android "$DEVICE" "$OUT/raw" &
    else
      boot "$UDID" "${region/_/-}" "$region"
      display=()
      if [ "$PLATFORM" = duo ]; then
        inner="$(inner_display "$UDID")"
        [ -n "$inner" ] || die "no 2007x2853 display on $UDID; is it an iPhone Duo?"
        display=(--display "$inner")
      fi
      python3 "$APP/tool/store_shutter.py" ${display[@]+"${display[@]}"} "$UDID" "$OUT/raw" &
    fi
    SHUTTER_PID=$!
    if [ "$PREVIEW" = 1 ]; then say "recording $run"; else say "capturing $run ($THEMES)"; fi
    capture "$run"
    kill "$SHUTTER_PID" 2> /dev/null || true
    wait "$SHUTTER_PID" 2> /dev/null || true
    SHUTTER_PID=""
  done

  # The iPad's pictures are taken sideways (the test locks the screen to
  # Flutter's landscapeLeft), but simctl saves them in the device's portrait
  # frame: each new one is turned upright first (IPAD_TURN degrees
  # clockwise). One of another size would land in no App Store slot, or the
  # wrong one.
  if [ "$PLATFORM" = ipad ]; then
    find "$OUT/raw" -name '*.png' -newer "$DEFINES" -print0 | while IFS= read -r -d '' shot; do
      if [ "$(sips -g pixelHeight "$shot" | awk '/pixelHeight/{print $2}')" = 2752 ]; then
        sips -r "${IPAD_TURN:-90}" "$shot" > /dev/null
      fi
    done
    python3 - "$OUT/raw" "$DEFINES" << 'PY' || die "the iPad's pictures are not all 2752x2064 (landscape)"
import os, struct, sys
raw, since = sys.argv[1], os.path.getmtime(sys.argv[2])
bad = []
for folder, _, names in os.walk(raw):
    for name in names:
        path = os.path.join(folder, name)
        if not name.endswith(".png") or os.path.getmtime(path) < since:
            continue
        with open(path, "rb") as f:
            size = struct.unpack(">II", f.read(24)[16:24])
        if size != (2752, 2064):
            bad.append(f"{path}: {size[0]}x{size[1]}")
print("\n".join(bad), file=sys.stderr)
sys.exit(1 if bad else 0)
PY
  fi

  # VELORKI_STORE_CREATIVE=1: the App Store's creative assets
  # (tool/store_creative.py) from the iPhone's pictures, made in the
  # background while the watch is shot (the simulator's work, not the
  # processor's) and done before the slides, whose six Chromes at once
  # left one of its pictures unwritten. They are uploaded with the set, so
  # a failure fails the run.
  if [ "${VELORKI_STORE_CREATIVE:-0}" = 1 ] && [ "$PLATFORM" = ios ] && [ -z "$UNTIL" ] \
    && [ "$PREVIEW" = 0 ]; then
    say "the creative assets, in the background"
    python3 "$APP/tool/store_creative.py" --locales "$LOCALES" > "$WORK/creative.log" 2>&1 &
    CREATIVE_PID=$!
  fi

  # The watch takes the figures of the ride, which comes last. The test
  # writes them for every language the store has, so --watch-locales can
  # shoot the watch for languages this run did not take.
  if [ -z "$UNTIL" ] && [ "$PREVIEW" = 0 ] && [ "$PLATFORM" = ios ] \
    && [ "${WATCH_LOCALES:-$LOCALES}" != none ]; then
    say "the watch, with the phone's figures"
    bash "$APP/tool/store_watch.sh" "$OUT/raw" "$OUT/watch" "${WATCH_LOCALES:-$LOCALES}" "${WATCH_THEME:-$THEMES}"
  fi
fi

if [ "$PREVIEW" = 1 ]; then
  say "making the preview"
  python3 "$APP/tool/store_preview.py" --locales "$LOCALES" \
    --clips "$OUT/raw/preview" --out "$OUT/preview"
  exit 0
fi

# Waits for the creative assets begun after the capture, if any.
creative_done() {
  [ -n "$CREATIVE_PID" ] || return 0
  local pid=$CREATIVE_PID
  CREATIVE_PID=""
  if wait "$pid"; then
    tail -n 2 "$WORK/creative.log"
  else
    cat "$WORK/creative.log" >&2
    die "the creative assets failed"
  fi
}

creative_done

# --no-slides stops here: the pictures (and the watch) only.
if [ "$SLIDES" = 0 ]; then
  exit 0
fi

say "making the slides"
if [ "$PLATFORM" != ios ]; then
  python3 "$APP/tool/store_slides.py" --platform "$PLATFORM" --locales "$LOCALES" ${NEED:+--set-only} \
    --shots "$SHOTS" --raw "$OUT/raw" --out "$OUT/slides" | tail -1
  exit 0
fi
python3 "$APP/tool/store_slides.py" --locales "$LOCALES" --shots "$SHOTS" ${NEED:+--set-only} \
  --raw "$OUT/raw" --watch "$OUT/watch" --out "$OUT/slides" | tail -1
