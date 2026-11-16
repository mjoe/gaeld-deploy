#!/bin/sh
# Erzeugt eine Env-Datei (Standard: .env) mit zufälligem APP_KEY und DB-Passwort (überschreibt nichts Bestehendes).
set -e
cd "$(dirname "$0")/.."
target="${1:-.env}"
if [ -f "$target" ]; then echo "$target existiert bereits – nichts zu tun."; exit 0; fi
cp .env.template "$target"
key="base64:$(openssl rand -base64 32)"
pw="$(openssl rand -hex 24)"
sed -i.bak "s|^APP_KEY=.*|APP_KEY=${key}|; s|^DB_PASSWORD=.*|DB_PASSWORD=${pw}|" "$target" && rm -f "$target.bak"
chmod 600 "$target"
echo "$target erzeugt. Bitte APP_URL anpassen, dann: docker compose up -d --build"
