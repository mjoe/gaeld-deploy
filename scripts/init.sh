#!/bin/sh
# Creates an env file (default: .env) with a random APP_KEY and DB password. Never overwrites an existing file.
set -e
cd "$(dirname "$0")/.." || exit 1
target="${1:-.env}"
if [ -f "$target" ]; then echo "$target already exists - nothing to do."; exit 0; fi
cp .env.template "$target"
key="base64:$(openssl rand -base64 32)"
pw="$(openssl rand -hex 24)"
sed -i.bak "s|^APP_KEY=.*|APP_KEY=${key}|; s|^DB_PASSWORD=.*|DB_PASSWORD=${pw}|" "$target" && rm -f "$target.bak"
chmod 600 "$target"
echo "$target created. Adjust APP_URL, then run: docker compose up -d --build"
