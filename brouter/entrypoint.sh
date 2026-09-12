#!/bin/sh
# Launch the BRouter standalone HTTP server.
#
# Mirrors upstream misc/scripts/standalone/server.sh, except that JAVA_OPTS is
# read from the environment instead of being overwritten (see Dockerfile).
#
# Upstream invocation contract (btools.server.RouteServer):
#   <segmentdir> <profile-map> <customprofiledir> <port> <maxthreads> [bindaddress]
set -eu

JAVA_OPTS="${JAVA_OPTS:--Xmx512M}"
SEGMENTSPATH="${SEGMENTSPATH:-/segments4}"
PROFILESPATH="${PROFILESPATH:-/profiles2}"
CUSTOMPROFILESPATH="${CUSTOMPROFILESPATH:-/customprofiles}"
BROUTER_PORT="${BROUTER_PORT:-17777}"
BROUTER_MAXTHREADS="${BROUTER_MAXTHREADS:-2}"
MAX_RUNNING_TIME="${MAX_RUNNING_TIME:-300}"

if [ ! -d "$SEGMENTSPATH" ]; then
  echo "brouter: segment directory $SEGMENTSPATH does not exist" >&2
  exit 1
fi
if [ ! -f "$PROFILESPATH/lookups.dat" ]; then
  echo "brouter: $PROFILESPATH/lookups.dat is missing - profiles not mounted?" >&2
  exit 1
fi
if [ -z "$(ls -A "$SEGMENTSPATH" 2>/dev/null | grep -i '\.rd5$' || true)" ]; then
  echo "brouter: WARNING no .rd5 segments in $SEGMENTSPATH yet." >&2
  echo "brouter: the server will start but every route will fail until" >&2
  echo "brouter: brouter-updater has finished its first sync." >&2
fi

echo "brouter: starting on port $BROUTER_PORT with JAVA_OPTS=$JAVA_OPTS"

# JAVA_OPTS is deliberately unquoted: it is a list of JVM flags, not one word.
# shellcheck disable=SC2086
exec java $JAVA_OPTS \
  -DmaxRunningTime="$MAX_RUNNING_TIME" \
  -DuseRFCMimeType=false \
  -cp /app/brouter.jar btools.server.RouteServer \
  "$SEGMENTSPATH" "$PROFILESPATH" "$CUSTOMPROFILESPATH" \
  "$BROUTER_PORT" "$BROUTER_MAXTHREADS"
