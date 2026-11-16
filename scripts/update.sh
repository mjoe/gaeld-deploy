#!/bin/sh
# Usage: scripts/update.sh v3.9.1   build an upstream release (SHA256-verified tarball)
#        scripts/update.sh main      build the upstream development head (or any branch, tag or commit)
# Backs up first, then builds the new image and restarts (migrations run in the entrypoint).
set -e
cd "$(dirname "$0")/.." || exit 1
[ -n "$1" ] || { echo "Please provide a release tag (e.g. v3.9.1) or a git ref (e.g. main)"; exit 1; }
case "$1" in v[0-9]*) source=release ;; *) source=git ;; esac
./scripts/backup.sh
for kv in "GAELD_SOURCE=$source" "GAELD_VERSION=$1"; do
    key="${kv%%=*}"
    if grep -q "^$key=" .env; then
        sed -i.bak "s|^$key=.*|$kv|" .env && rm -f .env.bak
    else
        echo "$kv" >> .env
    fi
done
docker compose up -d --build
docker compose exec -T app cat /var/www/html/.gaeld-rev
