# shellcheck shell=bash
# Shared settings for the BRouter oracle harness. Sourced, never executed.

ORACLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ORACLE_DIR/../.." && pwd)"

CACHE_DIR="$ORACLE_DIR/.cache"
SEGMENTS_DIR="$CACHE_DIR/segments4"
# Where fetch.sh moves tiles that failed to download or failed their checksum,
# so that SEGMENTS_DIR never holds bytes the corpus was not recorded against.
BAD_SEGMENTS_DIR="$CACHE_DIR/segments4-bad"
ZIP_DIR="$CACHE_DIR/zip"
CUSTOM_PROFILES_DIR="$CACHE_DIR/customprofiles"

# The profiles are *reused* from the repo, never copied.
PROFILES_DIR="$REPO_ROOT/brouter/profiles"

BROUTER_VERSION="$(cat "$REPO_ROOT/brouter/UPSTREAM_VERSION")"   # e.g. v1.7.10
BROUTER_VERSION_NUM="${BROUTER_VERSION#v}"                        # e.g. 1.7.10

BROUTER_ZIP_URL="https://github.com/abrensch/brouter/releases/download/${BROUTER_VERSION}/brouter-${BROUTER_VERSION_NUM}.zip"
BROUTER_ZIP="$CACHE_DIR/brouter-${BROUTER_VERSION_NUM}.zip"
# Path of the fat jar *inside* the release zip (verified for 1.7.10).
JAR_IN_ZIP="brouter-${BROUTER_VERSION_NUM}/brouter-${BROUTER_VERSION_NUM}-all.jar"
BROUTER_JAR="$ZIP_DIR/$JAR_IN_ZIP"

# The rd5 tiles come from an immutable snapshot release in orkitec/velorki-data,
# NOT from brouter.de: brouter.de rebuilds segments4 every night, so it can never
# serve the exact bytes the corpus and the brouter_dart fixtures were recorded
# against (tiles.sha256). Plain release-asset URLs need no token and do not touch
# the GitHub API rate limit.
ORACLE_TILES_TAG="oracle-20260912"
SEGMENTS_BASE_URL="${BROUTER_SEGMENTS_BASE_URL:-https://github.com/orkitec/velorki-data/releases/download/$ORACLE_TILES_TAG}"

# Where that snapshot was taken from, for the record and for re-recording.
UPSTREAM_SEGMENTS_URL="https://brouter.de/brouter/segments4"

PORT="${BROUTER_ORACLE_PORT:-17777}"
BASE_URL="http://127.0.0.1:${PORT}/brouter"
PID_FILE="$CACHE_DIR/routeserver.pid"
SERVER_LOG="$CACHE_DIR/routeserver.log"

# Java 17. Honour JAVA_HOME, else the mise temurin install, else PATH.
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
  JAVA_BIN="$JAVA_HOME/bin"
elif command -v mise >/dev/null 2>&1 && mise where java@temurin-17.0.20+101 >/dev/null 2>&1; then
  JAVA_BIN="$(mise where java@temurin-17.0.20+101)/bin"
else
  JAVA_BIN="$(dirname "$(command -v java)")"
fi
JAVA="$JAVA_BIN/java"
JAVAC="$JAVA_BIN/javac"
