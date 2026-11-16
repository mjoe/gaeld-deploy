# gaeld-deploy

Lean production setup for [Gäld](https://github.com/Scanix/Gaeld) (Community Edition, AGPL-3.0), a Swiss
double-entry accounting application.

It downloads the official release tarball (SHA256-verified) and builds a small image from it,
**without modifying the upstream source code**. Upstream only ships a Laravel Sail development compose file.

Services: `app` (nginx + PHP-FPM + queue worker + scheduler), `db` (PostgreSQL 16), `redis` (Valkey 8).
Redis is required: Gäld uses `Cache::tags()`, which the `database` cache driver does not support.

## Installation

```bash
./scripts/init.sh                 # creates .env (random APP_KEY and DB password)
nano .env                         # set APP_URL (behind HTTPS: SESSION_SECURE_COOKIE=true)
docker compose up -d --build
docker compose exec -u www-data app php artisan gaeld:install   # interactive: admin user + organization
```

The app listens on `http://127.0.0.1:8080`. For LAN access set `APP_BIND=0.0.0.0`; for HTTPS put a reverse proxy
(Caddy, Traefik, nginx, ...) in front of port 8080.

**Known upstream bug (v3.9.0):** `gaeld:install` does not set `email_verified_at` (missing from `$fillable`),
so the admin is redirected to `/email/verify` after the first login. Workaround:

```bash
docker compose exec db sh -c 'psql -U "$POSTGRES_USER" "$POSTGRES_DB" -c "update users set email_verified_at=now() where email_verified_at is null;"'
```

## Operations

```bash
./scripts/backup.sh                   # DB dump + uploaded files to ./backups (14 days retention)
./scripts/restore.sh backups/db-<timestamp>.sql.gz [backups/storage-<timestamp>.tar.gz]
./scripts/update.sh v3.9.1           # backup, build an upstream release (SHA256-verified), migrations run on startup
./scripts/update.sh main              # same, but build the upstream development head (or any branch/tag/commit)
./scripts/smoke-test.sh               # end-to-end test in an isolated compose project (port 18080)
docker compose logs -f app
```

Options in `.env`:

| Variable | Default | Purpose |
|---|---|---|
| `GAELD_SOURCE` | `release` | `release` = release tarball (SHA256-verified), `git` = build a git ref |
| `GAELD_VERSION` | `v3.9.0` | Release tag, or git ref (`main`, branch, tag, commit) when `GAELD_SOURCE=git` |
| `INSTALL_OCR` | `false` | Install Tesseract for receipt OCR (larger image) |
| `ALLOW_REGISTRATION` | `false` | Allow public self-registration at `/register` |
| `APP_BIND` / `APP_PORT` | `127.0.0.1` / `8080` | Published address and port |
| `MAIL_*` | empty | SMTP settings (see below) |

## Notes

- **Architectures:** the image builds natively for `amd64` and `arm64`. Build on the target architecture
  (`docker compose build`, roughly 2-5 minutes); cross-architecture builds under emulation (QEMU) are not supported
  and can crash while compiling the PHP extensions.
- **Registration:** `/register` is blocked by default (nginx returns 404). Without this, anyone who can reach the
  instance could create their own organization. Enable it with `ALLOW_REGISTRATION=true`, then
  `docker compose up -d`. The "Create account" link on the login page stays visible but leads to a 404.
- **Mail:** without SMTP settings (`MAIL_HOST`, ...) password-reset and verification mails are lost (errors in the log).
- **Backups:** test the restore regularly and keep copies off the host. Swiss law requires business records
  to be kept for 10 years.
- `docker compose down -v` deletes all data.

The exact upstream version of a running instance is stored in the image:
`docker compose exec app cat /var/www/html/.gaeld-rev` (for git builds it includes the resolved commit).
Development heads can contain unreleased migrations and breaking changes: back up first (`update.sh` does) and
expect that going back to an older version may not be possible.

## CI

GitHub Actions runs ShellCheck, Hadolint and a full smoke test (build, install, login, cache tags, queue worker,
restart persistence) on every push. The arm64 job only runs for public repositories.

A daily "Upstream watch" workflow smoke-tests the upstream development head (`main`) and opens an issue when it
breaks. It also opens an issue when a newer upstream release than the default exists, including the smoke test
result for that release.

## License

The files in this repository (Dockerfile, compose file, scripts, CI configuration) are licensed under the
[MIT License](LICENSE).

Gäld itself is licensed under AGPL-3.0-or-later (upstream: <https://github.com/Scanix/Gaeld>) and is not part of
this repository. It is downloaded at build time, so a built image contains AGPL-licensed code: if you distribute or
offer such an image or service to others, the AGPL obligations for Gäld apply to that part.
