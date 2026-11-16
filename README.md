# gaeld-deploy

Schlankes Produktions-Setup für [Gäld](https://github.com/Scanix/Gaeld) (Community Edition, AGPL-3.0).
Lädt das offizielle Release-Tarball (SHA256-geprüft) und baut daraus ein Image – **ohne Änderungen am Quellcode**.

Dienste: `app` (nginx + PHP-FPM + Queue-Worker + Scheduler), `db` (PostgreSQL 16), `redis` (Valkey 8).
Redis ist nötig: Gäld nutzt `Cache::tags()`, das der `database`-Cache nicht unterstützt.

## Installation
```bash
./scripts/init.sh                 # erzeugt .env (APP_KEY, DB-Passwort)
nano .env                         # APP_URL anpassen (bei HTTPS: SESSION_SECURE_COOKIE=true)
docker compose up -d --build
docker compose exec -u www-data app php artisan gaeld:install   # interaktiv: Admin + Organisation
```
Erreichbar unter `http://127.0.0.1:8080`. Für LAN-Zugriff `APP_BIND=0.0.0.0`, für HTTPS einen Reverse Proxy
(DSM-Reverse-Proxy, Caddy, Traefik) auf Port 8080 setzen.

**Bekannter Upstream-Fehler (v3.8.28):** `gaeld:install` setzt `email_verified_at` nicht (fehlt in `$fillable`),
der Admin wird danach auf `/email/verify` umgeleitet. Workaround:
```bash
docker compose exec db sh -c 'psql -U "$POSTGRES_USER" "$POSTGRES_DB" -c "update users set email_verified_at=now() where email_verified_at is null;"'
```

## Betrieb
```bash
./scripts/backup.sh                   # DB + Belege nach ./backups (14 Tage Rotation)
./scripts/restore.sh backups/db-….sql.gz [backups/storage-….tar.gz]
./scripts/update.sh v3.8.29           # Backup, neue Version bauen, Migrationen laufen beim Start
docker compose logs -f app
```
Optionen in `.env`: `INSTALL_OCR=true` (Tesseract für Belegerkennung, grösseres Image), SMTP-Variablen für Mailversand.

## Hinweise
- **Synology (x86):** Image direkt dort bauen (`docker compose build`, ca. 2–5 Min.). Ein amd64-Build auf Apple Silicon
  scheitert unter QEMU (Segfault beim Kompilieren der PHP-Erweiterungen); dafür eine CI mit amd64-Runner oder den nativen Build nutzen.
- **Registrierung:** `/register` ist standardmässig gesperrt (nginx liefert 404), weil sich sonst jeder mit Zugriff eine eigene
  Organisation anlegen könnte. Freigeben mit `ALLOW_REGISTRATION=true` in `.env`, dann `docker compose up -d`.
  Der Link «Konto erstellen» auf der Login-Seite bleibt sichtbar, führt dann aber ins Leere.
- **Mail:** Ohne SMTP-Konfiguration (`MAIL_HOST` …) gehen Passwort-Reset- und Verifikationsmails verloren (Fehler im Log).
- Backups regelmässig testen und ausserhalb des Hosts ablegen (Geschäftsbücher: 10 Jahre Aufbewahrung).
- `docker compose down -v` löscht alle Daten.
