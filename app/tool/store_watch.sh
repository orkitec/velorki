#!/usr/bin/env bash
# The watch half of the store screenshots: the watch app's ride screen with
# exactly the figures the phone showed at the same moment of the same ride.
#
#   tool/store_watch.sh <raw-dir> <out-dir> <locales> <themes>
#
# Reads <raw-dir>/<theme>/<locale>/activity.json, which the capture test
# writes from the snapshot the phone's live card was built from, and saves
# <out-dir>/<theme>/<locale>/riding.png, 422x514 from an Apple Watch Ultra 3
# (49mm) simulator, or the one VELORKI_STORE_WATCH_SIM names; one is created
# on the newest watchOS runtime when there is none.
#
# Beside it, <out-dir>/<theme>/<locale>/store/ gets the App Store's watch
# screenshots in four states: 1-riding-turn (with the next turn), 2-riding
# (without), 3-paused and 4-idle (no ride), with the heart held still. Their
# figures come from store/watch_store.json, written in the capture's decimal
# separator, and the turn's words from the app's strings for the locale.
#
# The app on the watch is the real RideView from ios/VelorkiWatch, compiled
# with store_watch/Stub.swift in place of RideSession: the stub takes the
# figures from the environment instead of from the phone. Nothing else of the
# watch app is involved, so no signing and no paired phone are needed.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW=$1 OUT=$2 LOCALES=$3 THEMES=$4
SRC=ios/VelorkiWatch
BUNDLE=com.orkitec.velorki.shot.watchkitapp
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

die() { printf 'store_watch: %s\n' "$*" >&2; exit 1; }

udid="${VELORKI_STORE_WATCH_SIM:-}"
if [ -z "$udid" ]; then
  udid="$(xcrun simctl list devices -j | python3 -c '
import json, sys
found = [d["udid"] for runtime, devices in sorted(json.load(sys.stdin)["devices"].items())
         if "watchOS" in runtime for d in devices
         if d["name"] == "Apple Watch Ultra 3 (49mm)" and d.get("isAvailable", True)]
print(found[-1] if found else "")
')"
fi
if [ -z "$udid" ]; then
  runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
watch = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "watchOS" and r["isAvailable"]]
print(max(watch, key=lambda r: [int(p) for p in r["version"].split(".")])["identifier"] if watch else "")
')"
  [ -n "$runtime" ] || die "no watchOS simulator runtime is installed (xcodebuild -downloadPlatform watchOS)"
  udid="$(xcrun simctl create "Apple Watch Ultra 3 (49mm)" \
    com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Ultra-3-49mm "$runtime")"
  printf '==> created Apple Watch Ultra 3 (49mm) (%s) on %s\n' "$udid" "$runtime"
fi

# RideView with its first page shown, compiled against the stub.
app="$WORK/Velorki.app"
mkdir -p "$app"
sed -e 's/TabView {/TabView(selection: .constant(0)) {/' \
  -e 's/ridePage.navigationTitle(title)/ridePage.navigationTitle(title).tag(0)/' \
  -e 's/morePage.navigationTitle(title)/morePage.navigationTitle(title).tag(1)/' \
  -e 's/isActive: ride.measuring/isActive: !shotStill \&\& ride.measuring/' \
  "$SRC/RideView.swift" > "$WORK/RideView.swift"
xcrun -sdk watchsimulator swiftc -target arm64-apple-watchos10.0-simulator \
  -parse-as-library -O "$WORK/RideView.swift" tool/store_watch/Stub.swift \
  -o "$app/VelorkiShot"
xcrun xcstringstool compile "$SRC/Localizable.xcstrings" --output-directory "$app" > /dev/null
cp tool/store_watch/Info.plist "$app/"
codesign -s - --force "$app" > /dev/null 2>&1

xcrun simctl boot "$udid" 2> /dev/null || true
xcrun simctl bootstatus "$udid" -b > /dev/null
xcrun simctl status_bar "$udid" override --time 9:41 2> /dev/null || true
xcrun simctl install "$udid" "$app"

# One `export NAME=value` line per figure of the capture, and one STORE_NAME
# (STORE_PAUSED_NAME) line per figure of the store shots, quoted for the shell.
cat > "$WORK/figures.py" << 'PY'
import json, os, shlex, sys
figures = json.load(open(sys.argv[1]))
store = json.load(open(sys.argv[2]))
locale, arbs = sys.argv[3], sys.argv[4]
names = {"distance": "DISTANCE", "elapsed": "ELAPSED", "speed": "SPEED",
         "heartRate": "HEART_RATE", "turnIcon": "TURN_ICON",
         "turnLabel": "TURN_LABEL", "turnDistance": "TURN_DISTANCE"}
for key, name in names.items():
    print(f"export SIMCTL_CHILD_SHOT_{name}={shlex.quote(str(figures.get(key, '')))}")

comma = "," in str(figures.get("speed", "")).split(" ")[0]
def decimal(value):
    text = f"{value:.1f}"
    return text.replace(".", ",") if comma else text
def string(key):
    for lang in (locale, "en"):
        path = os.path.join(arbs, f"app_{lang}.arb")
        if os.path.exists(path) and key in (arb := json.load(open(path))):
            return arb[key]
    sys.exit(f"store_watch: no string {key}")
riding, paused = store["riding"], store["paused"]
turn = riding["turn"]
shots = {
    "STORE_DISTANCE": f"{decimal(riding['distanceKm'])} km",
    "STORE_ELAPSED": riding["elapsed"],
    "STORE_SPEED": f"{decimal(riding['speedKmh'])} km/h",
    "STORE_HEART_RATE": riding["heartRate"],
    "STORE_TURN_ICON": turn["icon"],
    "STORE_TURN_LABEL": string(turn["label"]),
    "STORE_TURN_DISTANCE": f"{turn['metres']} m",
    "STORE_PAUSED_SPEED": f"{decimal(paused['speedKmh'])} km/h",
    "STORE_PAUSED_HEART_RATE": paused["heartRate"],
}
for name, value in shots.items():
    print(f"{name}={shlex.quote(str(value))}")
PY

# shoot <png>: the app launched afresh with the SIMCTL_CHILD_ figures, saved.
# A launch right after a terminate is now and then refused ("Scene update
# failed") on a slow machine; it is tried again after a pause.
shoot() {
  local try
  for try in 1 2 3 4; do
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" \
      -AppleLanguages "($locale)" -AppleLocale "$region" > /dev/null && break
    [ "$try" -lt 4 ] || die "the watch app would not launch"
    xcrun simctl terminate "$udid" "$BUNDLE" 2> /dev/null || true
    sleep $((try * 5))
  done
  sleep 3
  mkdir -p "$(dirname "$1")"
  xcrun simctl io "$udid" screenshot "$1" > /dev/null 2>&1
  echo "$1"
}

IFS=, read -r -a locales <<< "$LOCALES"
IFS=, read -r -a themes <<< "$THEMES"
for theme in "${themes[@]}"; do
  for locale in "${locales[@]}"; do
    data="$RAW/$theme/$locale/activity.json"
    [ -f "$data" ] || die "missing $data; run the capture first"
    python3 "$WORK/figures.py" "$data" store/watch_store.json "$locale" lib/l10n > "$WORK/figures.sh"
    # shellcheck disable=SC1091
    source "$WORK/figures.sh"
    region=$locale
    case "$locale" in
      en) region=en_US ;; de) region=de_DE ;; fr) region=fr_FR ;;
      es) region=es_ES ;; it) region=it_IT ;; nl) region=nl_NL ;;
    esac
    export SIMCTL_CHILD_SHOT_STATUS=active SIMCTL_CHILD_SHOT_STILL=''
    shoot "$OUT/$theme/$locale/riding.png"

    store="$OUT/$theme/$locale/store"
    export SIMCTL_CHILD_SHOT_STILL=1 \
      SIMCTL_CHILD_SHOT_DISTANCE="$STORE_DISTANCE" SIMCTL_CHILD_SHOT_ELAPSED="$STORE_ELAPSED" \
      SIMCTL_CHILD_SHOT_SPEED="$STORE_SPEED" SIMCTL_CHILD_SHOT_HEART_RATE="$STORE_HEART_RATE" \
      SIMCTL_CHILD_SHOT_TURN_ICON="$STORE_TURN_ICON" SIMCTL_CHILD_SHOT_TURN_LABEL="$STORE_TURN_LABEL" \
      SIMCTL_CHILD_SHOT_TURN_DISTANCE="$STORE_TURN_DISTANCE"
    shoot "$store/1-riding-turn.png"
    export SIMCTL_CHILD_SHOT_TURN_ICON='' SIMCTL_CHILD_SHOT_TURN_LABEL='' SIMCTL_CHILD_SHOT_TURN_DISTANCE=''
    shoot "$store/2-riding.png"
    export SIMCTL_CHILD_SHOT_STATUS=paused SIMCTL_CHILD_SHOT_SPEED="$STORE_PAUSED_SPEED" \
      SIMCTL_CHILD_SHOT_HEART_RATE="$STORE_PAUSED_HEART_RATE"
    shoot "$store/3-paused.png"
    export SIMCTL_CHILD_SHOT_STATUS=idle SIMCTL_CHILD_SHOT_HEART_RATE=''
    shoot "$store/4-idle.png"
  done
done
xcrun simctl shutdown "$udid" 2> /dev/null || true
