#!/usr/bin/env bash
# Install BRouter as a systemd service, without Docker.
#
# Downloads the pinned upstream release zip, installs the server jar, the
# profiles from this repo and the segment sync script into /opt/brouter, then
# enables brouter.service and the weekly brouter-sync.timer.
#
# Usage:  sudo ./install-systemd.sh [version]     (default: ../../brouter/UPSTREAM_VERSION)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_BROUTER="$(cd "$HERE/../../brouter" && pwd)"
PREFIX=/opt/brouter
VERSION="${1:-$(tr -d '[:space:]' < "$REPO_BROUTER/UPSTREAM_VERSION")}"
NUM="${VERSION#v}"                       # v1.7.10 -> 1.7.10
ZIP="brouter-${NUM}.zip"
URL="https://github.com/abrensch/brouter/releases/download/${VERSION}/${ZIP}"

[ "$(id -u)" = "0" ] || { echo "run as root" >&2; exit 1; }
command -v java >/dev/null || { echo "java 17+ is required (apt install openjdk-17-jre-headless)" >&2; exit 1; }
command -v unzip >/dev/null || { echo "unzip is required" >&2; exit 1; }
command -v curl  >/dev/null || { echo "curl is required" >&2; exit 1; }

echo "==> installing BRouter $VERSION into $PREFIX"

id -u brouter >/dev/null 2>&1 || useradd --system --home-dir "$PREFIX" --shell /usr/sbin/nologin brouter
mkdir -p "$PREFIX"/{bin,segments4,profiles2,customprofiles}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "==> downloading $URL"
curl -fsSL --retry 3 -o "$tmp/$ZIP" "$URL"
unzip -q -o "$tmp/$ZIP" -d "$tmp/x"

# The release zip ships the shaded server jar as brouter-<version>-all.jar at
# the top of the archive (lib/ holds third-party jars we must not pick up).
jar="$(find "$tmp/x" -name 'brouter*-all.jar' -type f | sort | head -n1)"
[ -n "$jar" ] || jar="$(find "$tmp/x" -name 'brouter*.jar' -type f -not -path '*/lib/*' | sort | head -n1)"
[ -n "$jar" ] || { echo "no brouter jar found inside $ZIP" >&2; exit 1; }
install -m 0644 "$jar" "$PREFIX/brouter.jar"
echo "==> installed $(basename "$jar") -> $PREFIX/brouter.jar"

# Profiles come from this repo (pinned + reviewed), not from the zip.
install -m 0644 "$REPO_BROUTER"/profiles/lookups.dat "$PREFIX/profiles2/"
install -m 0644 "$REPO_BROUTER"/profiles/*.brf       "$PREFIX/profiles2/"

install -m 0755 "$REPO_BROUTER/updater/sync.sh" "$PREFIX/bin/sync.sh"

chown -R brouter:brouter "$PREFIX"

install -m 0644 "$HERE/brouter.service"      /etc/systemd/system/brouter.service
install -m 0644 "$HERE/brouter-sync.service" /etc/systemd/system/brouter-sync.service
install -m 0644 "$HERE/brouter-sync.timer"   /etc/systemd/system/brouter-sync.timer

systemctl daemon-reload
systemctl enable --now brouter-sync.timer
systemctl enable brouter.service

cat <<MSG

Installed. Next steps:

  1. Fetch segments (hours for the planet; edit SEGMENT_FILTER in
     /etc/systemd/system/brouter-sync.service to limit the area first):
         systemctl start brouter-sync.service
         journalctl -fu brouter-sync.service

  2. Once tiles exist, start the router:
         systemctl start brouter.service

  3. Verify (on the host):
         curl 'http://localhost:17777/brouter?lonlats=8.5,47.4|8.51,47.41&profile=trekking&alternativeidx=0&format=geojson'

  BRouter listens on 17777 only. Put it behind your own TLS terminator and do
  not expose 17777 to the internet.
MSG
