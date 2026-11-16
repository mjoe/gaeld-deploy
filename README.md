# gaeld-deploy

> Unofficial community deployment setup for Gäld. Not affiliated with the Gäld project.

Lean production setup for [Gäld](https://github.com/Scanix/Gaeld) (Community Edition, AGPL-3.0), a Swiss
double-entry accounting application.

It downloads the official release tarball (SHA256-verified) and builds a small image from it,
**without modifying the upstream source code**. Upstream only ships a Laravel Sail development compose file.

Services: `app` (nginx + PHP-FPM + queue worker + scheduler), `db` (PostgreSQL 16), `redis` (Valkey 8).
Redis is required: Gäld uses `Cache::tags()`, which the `database` cache driver does not support.

## Requirements

Docker Engine 24+ with Docker Compose v2.17+ (`docker compose`), on `amd64` or `arm64`.
About 1 GB of RAM is enough for a small instance (the three containers use roughly 250 MB when idle).

## Installation

```bash
./scripts/init.sh                 # creates .env (random APP_KEY and DB password)
nano .env                         # set APP_URL (see HTTPS below)
docker compose up -d --build
docker compose exec -u www-data app php artisan gaeld:install   # interactive: admin user + organization
```

**Known upstream bug (v3.9.0):** `gaeld:install` does not set `email_verified_at` (missing from `$fillable`),
so the admin is redirected to `/email/verify` after the first login. Workaround:

```bash
docker compose exec db sh -c 'psql -U "$POSTGRES_USER" "$POSTGRES_DB" -c "update users set email_verified_at=now() where email_verified_at is null;"'
```

### HTTPS

The stack does **not** include a reverse proxy. The image only contains an internal nginx that serves the application
over plain HTTP on port 8080 (it is not meant to be exposed and does not handle certificates). For HTTPS, run the
reverse proxy you already use in front of it. Any proxy works as long as it terminates TLS and forwards the `Host`,
`X-Forwarded-For` and `X-Forwarded-Proto` headers to `127.0.0.1:8080`. Then set in `.env` and run `docker compose up -d`:

```
APP_URL=https://gaeld.example.com
SESSION_SECURE_COOKIE=true
```

The default setup publishes the port on `127.0.0.1:8080` only, so only a proxy on the same host can reach it.
For direct access from your LAN without HTTPS set `APP_BIND=0.0.0.0`.

Minimal examples for a proxy on the same host (not covered by the smoke test):

**Caddy** (obtains and renews Let's Encrypt certificates automatically):

```
gaeld.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

**nginx** (certificates, for example from certbot, are managed by you):

```
server {
    listen 443 ssl;
    server_name gaeld.example.com;
    ssl_certificate     /etc/letsencrypt/live/gaeld.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/gaeld.example.com/privkey.pem;
    client_max_body_size 20M;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 120s;
    }
}
```

Traefik, Nginx Proxy Manager, Cloudflare Tunnel and similar tools work the same way: forward to port 8080 with the
headers above.

**Proxy on another host:**

- Publish the port on an address the proxy can reach (`APP_BIND` = the host's LAN address) and allow only the proxy to
  connect to port 8080. Ports published by Docker bypass host firewalls such as `ufw` or `firewalld`, so bind to a
  specific address or add rules to Docker's `DOCKER-USER` chain.
- Set `TRUSTED_PROXIES` in `.env` to the proxy's IP address or CIDR range instead of the default `*`.
  It defines whose `X-Forwarded-*` headers Gäld believes (real client IP and original scheme). If it is too permissive
  and port 8080 is reachable directly, anyone can forge their IP, which bypasses IP-based rate limits and falsifies
  the audit log. `*` is only safe in the default setup above.

Never expose port 8080 directly to the internet.

## Operations

```bash
./scripts/backup.sh                   # DB dump + uploaded files to ./backups (14 days retention)
./scripts/restore.sh backups/db-<timestamp>.sql.gz [backups/storage-<timestamp>.tar.gz]
./scripts/update.sh v3.9.1           # backup, build an upstream release (SHA256-verified), migrations run on startup
./scripts/update.sh main              # same, but build the upstream development head (or any branch/tag/commit)
./scripts/smoke-test.sh               # end-to-end test in an isolated compose project (port 18080)
docker compose logs -f app
```

**Rollback:** `update.sh` takes a backup first. If an upgrade goes wrong, set the previous `GAELD_VERSION` in `.env`,
rebuild (`docker compose up -d --build`) and restore the backup made before the upgrade with `restore.sh`.
Do not run an older version against a database that a newer version has already migrated.
`restore.sh` asks for confirmation, replaces the database, and flushes the Redis cache (which also ends all sessions).

Options in `.env`:

| Variable | Default | Purpose |
|---|---|---|
| `GAELD_SOURCE` | `release` | `release` = release tarball (SHA256-verified), `git` = build a git ref |
| `GAELD_VERSION` | `v3.9.0` | Release tag, or git ref (`main`, branch, tag, commit) when `GAELD_SOURCE=git` |
| `INSTALL_OCR` | `false` | Install Tesseract for receipt OCR (larger image; not covered by the smoke test) |
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
- **Image size:** roughly 500 MB, mostly PHP, its extensions and the application's Composer dependencies.
- **Backups:** `backup.sh` writes files readable by the current user only, and removes partial files if a step fails.
  The smoke test covers a backup/restore round trip. Test the restore regularly and keep copies off the host. Swiss law requires business records
  to be kept for 10 years.
- `docker compose down -v` deletes all data.

The exact upstream version of a running instance is stored in the image:
`docker compose exec app cat /var/www/html/.gaeld-rev` (for git builds it includes the resolved commit).
Development heads can contain unreleased migrations and breaking changes: back up first (`update.sh` does) and
expect that going back to an older version may not be possible.

## CI

GitHub Actions runs ShellCheck, Hadolint and a full smoke test (build, install, login, cache tags, queue worker,
restart persistence, backup and restore) on every push. The arm64 job only runs for public repositories.

A daily "Upstream watch" workflow smoke-tests the upstream development head (`main`) and opens an issue when it
breaks. It also opens an issue when a newer upstream release than the default exists, including the smoke test
result for that release.

## License

The files in this repository (Dockerfile, compose file, scripts, CI configuration) are licensed under the
[MIT License](LICENSE).

Gäld itself is licensed under AGPL-3.0-or-later (upstream: <https://github.com/Scanix/Gaeld>) and is not part of
this repository. It is downloaded at build time, so a built image contains AGPL-licensed code: if you distribute or
offer such an image or service to others, the AGPL obligations for Gäld apply to that part.
