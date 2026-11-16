#!/bin/sh
# Sichert DB-Dump + storage-Volume nach ./backups (Rotation: 14 Tage)
set -e
cd "$(dirname "$0")/.." || exit 1
ts=$(date +%F_%H%M)
dir=backups; mkdir -p "$dir"
docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' | gzip > "$dir/db-$ts.sql.gz"
docker compose exec -T app tar -C /var/www/html -czf - storage/app > "$dir/storage-$ts.tar.gz"
find "$dir" -type f -mtime +14 -delete
echo "Backup: $dir/db-$ts.sql.gz, $dir/storage-$ts.tar.gz"
