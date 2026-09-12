#!/usr/bin/env bash
# Stop the RouteServer started by serve.sh. Works from any cwd, idempotent.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [ ! -f "$PID_FILE" ]; then
  echo "not running (no $PID_FILE)" >&2
  exit 0
fi
pid="$(cat "$PID_FILE")"
if kill -0 "$pid" 2>/dev/null; then
  kill "$pid"
  for _ in $(seq 1 40); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
  kill -9 "$pid" 2>/dev/null || true
  echo "stopped pid $pid" >&2
else
  echo "stale pid file for $pid" >&2
fi
rm -f "$PID_FILE"
