#!/bin/sh
# Usage: scripts/update.sh v3.8.29  – sichert, baut neues Image, startet neu (Migrationen laufen im Entrypoint)
set -e
cd "$(dirname "$0")/.."
[ -n "$1" ] || { echo "Version angeben, z.B. v3.8.29"; exit 1; }
./scripts/backup.sh
sed -i.bak "s|^GAELD_VERSION=.*|GAELD_VERSION=$1|" .env && rm -f .env.bak
docker compose up -d --build
