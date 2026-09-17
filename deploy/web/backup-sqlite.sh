#!/usr/bin/env bash
# Nightly backup of the share-link database.
#
# `sqlite3 .backup` is the only correct way to copy a live SQLite file: the
# database runs in WAL mode with two workers writing, so `cp` can produce a
# torn copy. `.backup` takes a consistent snapshot while the app keeps running.
#
#   sudo install -m 0755 backup-sqlite.sh /usr/local/bin/velorki-backup-sqlite
#   sudo -u velorki /usr/local/bin/velorki-backup-sqlite
#   printf '%s\n' '23 3 * * * velorki /usr/local/bin/velorki-backup-sqlite >>/var/log/velorki-backup.log 2>&1' \
#     | sudo tee /etc/cron.d/velorki-backup
#
# Restore: stop the app, gunzip the file over /var/lib/velorki/share.sqlite,
# delete any -wal/-shm left beside it, start the app. See docs/DEPLOY_WEB.md.
set -euo pipefail

DB=${SHARE_DB_PATH:-/var/lib/velorki/share.sqlite}
DEST=${BACKUP_DIR:-/var/backups/velorki}
KEEP_DAYS=${KEEP_DAYS:-30}

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

command -v sqlite3 >/dev/null 2>&1 || { log "ERROR: sqlite3 not installed"; exit 1; }
[ -f "$DB" ] || { log "ERROR: no database at $DB"; exit 1; }

install -d -m 0700 "$DEST"
stamp=$(date -u +%Y-%m-%d)
out="$DEST/share-$stamp.sqlite"

# Quoting: the path goes inside the SQL string, so it is single-quoted there.
sqlite3 "$DB" ".backup '$out'"
# Cheap integrity check on the copy before the old ones are rotated away.
if [ "$(sqlite3 "$out" 'PRAGMA integrity_check;')" != "ok" ]; then
  log "ERROR: integrity_check failed on $out, keeping it and stopping"
  exit 1
fi

gzip -f "$out"
chmod 0600 "$out.gz"
log "wrote $out.gz ($(stat -c %s "$out.gz") bytes)"

# Rotation. -mtime is in whole days; +30 deletes the 31st day onwards.
find "$DEST" -maxdepth 1 -name 'share-*.sqlite.gz' -type f -mtime "+$KEEP_DAYS" -print -delete \
  | while read -r old; do log "removed $old"; done

log "done"
