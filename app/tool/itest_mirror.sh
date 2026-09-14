#!/usr/bin/env bash
# Builds the routing-tile mirror the integration tests download from, out of
# the frozen oracle tile, and serves it on port 8000 in the background.
#
#   tool/itest_mirror.sh [mirror-dir]        (ITEST_MIRROR_PORT overrides 8000)
#
# Used by the Android and the iOS integration workflows; the emulator reaches
# it as http://10.0.2.2:8000, the iOS simulator as http://127.0.0.1:8000.
# An altered tile stops here with a message that says what to look at:
# serving nothing would leave every test failing later with "the mirror
# manifest lacks W20_N30", which reads like a bug in the app.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mirror="${1:-$root/.itest-mirror}"
tile="${ORACLE_TILE:-W20_N30}"
port="${ITEST_MIRROR_PORT:-8000}"
format_version="${RD5_FORMAT_VERSION:-11.2}"
src="$root/tools/brouter-oracle/tiles/${tile}.rd5"

mkdir -p "$mirror"
if [ ! -f "$src" ]; then
  echo "::error::$src is missing. The oracle tiles are committed fixtures;"
  echo "::error::see tools/brouter-oracle/tiles/README.md."
  exit 1
fi
echo "==> copying $src"
cp -f "$src" "$mirror/${tile}.rd5"

echo "==> verifying against tools/brouter-oracle/tiles.sha256"
want=$(awk -v t="${tile}.rd5" '$2 == t || $2 == "./" t {print $1}' \
  "$root/tools/brouter-oracle/tiles.sha256")
if [ -z "$want" ]; then
  echo "::error::tools/brouter-oracle/tiles.sha256 has no entry for ${tile}.rd5."
  exit 1
fi
if command -v sha256sum >/dev/null; then
  got=$(sha256sum "$mirror/${tile}.rd5" | cut -d' ' -f1)
else
  got=$(shasum -a 256 "$mirror/${tile}.rd5" | cut -d' ' -f1)
fi
if [ "$want" != "$got" ]; then
  echo "::error::${tile}.rd5 does not match tiles.sha256 (want $want, got $got)."
  echo "::error::The corpus is bound to exactly these bytes; investigate before re-recording."
  rm -f "$mirror/${tile}.rd5"
  exit 1
fi

echo "==> writing manifest.json"
ORACLE_TILE="$tile" RD5_FORMAT_VERSION="$format_version" python3 - "$mirror" <<'PY'
import hashlib, json, os, sys, datetime
mirror = sys.argv[1]
tile = os.environ["ORACLE_TILE"]
path = os.path.join(mirror, tile + ".rd5")
data = open(path, "rb").read()
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
manifest = {
    "formatVersion": os.environ["RD5_FORMAT_VERSION"],
    "generatedAt": stamp,
    "tiles": [{
        "tile": tile,
        "bytes": len(data),
        "updatedAt": stamp,
        "sha256": hashlib.sha256(data).hexdigest(),
    }],
}
with open(os.path.join(mirror, "manifest.json"), "w") as out:
    json.dump(manifest, out, indent=1)
print(json.dumps(manifest, indent=1))
PY

echo "==> serving $mirror on port $port"
nohup python3 -m http.server "$port" --directory "$mirror" > "$root/mirror.log" 2>&1 &
echo $! > "$root/mirror.pid"
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$port/manifest.json" > /dev/null; then
    echo "==> mirror is up"
    exit 0
  fi
  sleep 1
done
echo "::error::The segments mirror did not come up on port $port."
cat "$root/mirror.log" || true
exit 1
