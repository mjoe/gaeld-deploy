#!/bin/sh
# Backs up a DB dump and the storage volume to ./backups (override with BACKUP_DIR; retention: 14 days).
set -e
cd "$(dirname "$0")/.." || exit 1
umask 077
ts=$(date +%F_%H%M)
dir="${BACKUP_DIR:-backups}"; mkdir -p "$dir"
tmp="$dir/.db-$ts.sql"; db="$dir/db-$ts.sql.gz"; files="$dir/storage-$ts.tar.gz"
# On any failure remove partial files, so a broken backup is never mistaken for a good one
# rc is assigned inside the trap string
# shellcheck disable=SC2154
trap 'rc=$?; rm -f "$tmp"; [ "$rc" -eq 0 ] || rm -f "$db" "$files"' EXIT

docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$tmp"
[ -s "$tmp" ] || { echo "ERROR: the database dump is empty" >&2; exit 1; }
gzip -c "$tmp" > "$db"
docker compose exec -T app tar -C /var/www/html -czf - storage/app > "$files"

find "$dir" -type f \( -name 'db-*.sql.gz' -o -name 'storage-*.tar.gz' \) -mtime +14 -delete
echo "Backup: $db, $files"
