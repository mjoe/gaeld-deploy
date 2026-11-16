#!/bin/sh
# Usage: scripts/update.sh v3.8.29  - backs up, builds the new image, restarts (migrations run in the entrypoint)
set -e
cd "$(dirname "$0")/.." || exit 1
[ -n "$1" ] || { echo "Please provide a version, e.g. v3.8.29"; exit 1; }
./scripts/backup.sh
sed -i.bak "s|^GAELD_VERSION=.*|GAELD_VERSION=$1|" .env && rm -f .env.bak
docker compose up -d --build
