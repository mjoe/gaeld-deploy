#!/bin/sh
# Usage: scripts/restore.sh backups/db-XXXX.sql.gz [backups/storage-XXXX.tar.gz]
# ACHTUNG: überschreibt die bestehende Datenbank.
set -e
cd "$(dirname "$0")/.."
[ -f "$1" ] || { echo "DB-Dump angeben"; exit 1; }
docker compose stop app
docker compose exec -T db sh -c 'dropdb -U "$POSTGRES_USER" --if-exists "$POSTGRES_DB" && createdb -U "$POSTGRES_USER" "$POSTGRES_DB"'
gunzip -c "$1" | docker compose exec -T db sh -c 'psql -q -U "$POSTGRES_USER" "$POSTGRES_DB"'
docker compose start app
if [ -n "$2" ]; then docker compose exec -T app tar -C /var/www/html -xzf - < "$2"; fi
echo "Restore abgeschlossen."
