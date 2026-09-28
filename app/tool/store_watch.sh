#!/usr/bin/env bash
# The watch half of the store screenshots: the watch app's ride screen with
# exactly the figures the phone showed at the same moment of the same ride.
#
#   tool/store_watch.sh <raw-dir> <out-dir> <locales> <themes>
#
# Reads <raw-dir>/<theme>/<locale>/activity.json, which the capture test
# writes from the snapshot the phone's live card was built from, and saves
# <out-dir>/<theme>/<locale>/riding.png, 422x514 from an Apple Watch Ultra 3
# (49mm) simulator, or the one VELORKI_STORE_WATCH_SIM names.
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
[ -n "$udid" ] || die "no Apple Watch Ultra 3 (49mm) simulator; create one or set VELORKI_STORE_WATCH_SIM"

# RideView with its first page shown, compiled against the stub.
app="$WORK/Velorki.app"
mkdir -p "$app"
sed -e 's/TabView {/TabView(selection: .constant(0)) {/' \
  -e 's/ridePage.navigationTitle(title)/ridePage.navigationTitle(title).tag(0)/' \
  -e 's/morePage.navigationTitle(title)/morePage.navigationTitle(title).tag(1)/' \
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

# One `export NAME=value` line per figure, quoted for the shell.
cat > "$WORK/figures.py" << 'PY'
import json, shlex, sys
figures = json.load(open(sys.argv[1]))
names = {"distance": "DISTANCE", "elapsed": "ELAPSED", "speed": "SPEED",
         "heartRate": "HEART_RATE", "turnIcon": "TURN_ICON",
         "turnLabel": "TURN_LABEL", "turnDistance": "TURN_DISTANCE"}
for key, name in names.items():
    print(f"export SIMCTL_CHILD_SHOT_{name}={shlex.quote(str(figures.get(key, '')))}")
PY

IFS=, read -r -a locales <<< "$LOCALES"
IFS=, read -r -a themes <<< "$THEMES"
for theme in "${themes[@]}"; do
  for locale in "${locales[@]}"; do
    data="$RAW/$theme/$locale/activity.json"
    [ -f "$data" ] || die "missing $data; run the capture first"
    python3 "$WORK/figures.py" "$data" > "$WORK/figures.sh"
    # shellcheck disable=SC1091
    source "$WORK/figures.sh"
    region=$locale
    case "$locale" in en) region=en_US ;; de) region=de_DE ;; esac
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" \
      -AppleLanguages "($locale)" -AppleLocale "$region" > /dev/null
    sleep 3
    mkdir -p "$OUT/$theme/$locale"
    xcrun simctl io "$udid" screenshot "$OUT/$theme/$locale/riding.png" > /dev/null 2>&1
    echo "$OUT/$theme/$locale/riding.png"
  done
done
xcrun simctl shutdown "$udid" 2> /dev/null || true
