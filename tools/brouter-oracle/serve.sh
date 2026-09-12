#!/usr/bin/env bash
# Start the pinned BRouter RouteServer against the cached rd5 tiles and the
# repo's own profiles. Works from any cwd; writes .cache/routeserver.pid.
#
#   ./serve.sh            start (fails if already running)
#   ./serve.sh --foreground   run in the foreground (used by nothing but debugging)
#
# Determinism: -DmaxRunningTime=0 disables BRouter's 60 s routing timeout
# (RouteServer.getMaxRunningTime() -> RoutingEngine, which guards every timeout
# check with `if (maxRunningTime > 0)`), so a slow machine can never truncate a
# search and change the result.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[ -f "$BROUTER_JAR" ] || { echo "no jar -- run ./fetch.sh first" >&2; exit 1; }
[ -d "$SEGMENTS_DIR" ] || { echo "no segments -- run ./fetch.sh first" >&2; exit 1; }
[ -f "$PROFILES_DIR/lookups.dat" ] || { echo "no lookups.dat in $PROFILES_DIR" >&2; exit 1; }
mkdir -p "$CUSTOM_PROFILES_DIR"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "already running as pid $(cat "$PID_FILE") on port $PORT" >&2
  exit 0
fi
rm -f "$PID_FILE"

# Refuse to start on a port that something else already owns -- otherwise the
# readiness probe below would happily talk to a stale server and the corpus
# would silently be recorded against the wrong segments or profiles.
if curl -fsS -o /dev/null --max-time 5 "http://127.0.0.1:${PORT}/robots.txt" 2>/dev/null; then
  echo "port $PORT is already serving something; stop it first (./stop.sh) " >&2
  exit 1
fi

# usage: java RouteServer <segmentdir> <profiledir> <customprofiledir> <port> <maxthreads>
CMD=( "$JAVA"
      -Xmx256M
      -DmaxRunningTime=0
      -cp "$BROUTER_JAR"
      btools.server.RouteServer
      "$SEGMENTS_DIR" "$PROFILES_DIR" "$CUSTOM_PROFILES_DIR" "$PORT" 4 )

if [ "${1:-}" = "--foreground" ]; then
  exec "${CMD[@]}"
fi

printf '%q ' "${CMD[@]}" > "$CACHE_DIR/routeserver.cmdline"; echo >> "$CACHE_DIR/routeserver.cmdline"
# cd into .cache so BRouter's optional stacks.txt sampler never picks up a repo
# file. `exec` matters: it makes the backgrounded subshell *become* the JVM, so
# $! is the pid of java itself and stop.sh really kills the server instead of a
# wrapper shell.
( cd "$CACHE_DIR" && exec nohup "${CMD[@]}" >"$SERVER_LOG" 2>&1 ) &
echo $! > "$PID_FILE"

# wait for the port to answer a real route request
for i in $(seq 1 60); do
  if curl -fsS -o /dev/null "$BASE_URL?lonlats=-16.9095,32.6459%7C-16.9010,32.6480&profile=trekking&alternativeidx=0&format=geojson" 2>/dev/null; then
    echo "RouteServer up on port $PORT (pid $(cat "$PID_FILE"))" >&2
    echo "  command: $(cat "$CACHE_DIR/routeserver.cmdline")" >&2
    exit 0
  fi
  kill -0 "$(cat "$PID_FILE")" 2>/dev/null || { echo "server died:" >&2; cat "$SERVER_LOG" >&2; exit 1; }
  sleep 0.5
done
echo "server did not become ready; log:" >&2
cat "$SERVER_LOG" >&2
exit 1
