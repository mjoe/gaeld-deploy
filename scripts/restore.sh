#!/bin/sh
# Usage: scripts/restore.sh backups/db-<timestamp>.sql.gz [backups/storage-<timestamp>.tar.gz]
# WARNING: overwrites the existing database. Set FORCE=1 to skip the confirmation prompt.
set -e
cd "$(dirname "$0")/.." || exit 1
[ -f "$1" ] || { echo "Please provide a DB dump file"; exit 1; }
if [ "${FORCE:-}" != "1" ]; then
    printf 'This overwrites the current database. Continue? [y/N] '
    read -r answer
    [ "$answer" = "y" ] || { echo "Aborted."; exit 1; }
fi
docker compose stop app
docker compose exec -T db sh -c 'dropdb -U "$POSTGRES_USER" --if-exists "$POSTGRES_DB" && createdb -U "$POSTGRES_USER" "$POSTGRES_DB"'
gunzip -c "$1" | docker compose exec -T db sh -c 'psql -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" "$POSTGRES_DB"'
# Gäld caches reports in Redis: drop stale entries (this also ends all sessions and clears the queue)
docker compose exec -T redis valkey-cli flushall >/dev/null
docker compose up -d --wait app
if [ -n "$2" ]; then docker compose exec -T app tar -C /var/www/html -xzf - < "$2"; fi
echo "Restore finished."
