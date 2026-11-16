# gaeld-deploy

> Unofficial community deployment setup for Gäld. Not affiliated with the Gäld project.

Lean production setup for [Gäld](https://github.com/Scanix/Gaeld) (Community Edition, AGPL-3.0), a Swiss
double-entry accounting application.

It builds a compact image from an official upstream release (SHA256-verified tarball) or from a git ref such as the
development head, **without modifying the upstream source code**. Upstream only ships a Laravel Sail development
compose file.

## Architecture and network flow

```
  Browser
     |
     | HTTPS :443
     v
  +----------------------------------------------+
  | TLS proxy: yours, not part of this stack     |
  | (Caddy, nginx, Traefik, ...)                 |
  +----------------------------------------------+
     |
     | HTTP 127.0.0.1:8080
     v
  +- compose stack -----------------------------------------------+
  |                                                               |
  |  +-----------------------------+  SQL :5432   +-------------+ |
  |  | app                         |------------->| db          | |
  |  | nginx :8080 -> PHP-FPM      |              | PostgreSQL  | |
  |  | + queue worker + scheduler  |              +-------------+ |
  |  |                             |                              |
  |  |                             |  :6379       +-------------+ |
  |  |                             |------------->| redis       | |
  |  +-----------------------------+              | Valkey      | |
  |       |                                       +-------------+ |
  +-------|-------------------------------------------------------+
          | SMTP (optional)
          v
 Mail server (yours)
```

Everything outside the "compose stack" box is not part of this repository.

- **`app`** is the only container that is published to the host, on `127.0.0.1:8080` by default. The nginx inside serves
  static files and passes PHP requests to PHP-FPM. The same container runs the queue worker and the scheduler.
- **`db`** (PostgreSQL 16) and **`redis`** (Valkey, a Redis-compatible store) are only reachable inside the compose
  network. Data lives in the named volumes `pgdata`, `redisdata` and `storage` (uploaded receipts, logs).
  Redis is required because Gäld uses `Cache::tags()`, which the `database` cache driver does not support.
- **HTTPS** is not handled by this stack, see [TLS and reverse proxy](#tls-and-reverse-proxy).

## Requirements

Docker Engine 24+ with Docker Compose v2.17+ (`docker compose`), on `amd64` or `arm64`.
About 1 GB of RAM is enough for a small instance (the three containers use roughly 250 MB when idle).

## Installation

```bash
./scripts/init.sh                 # creates .env (random APP_KEY and DB password)
nano .env                         # set APP_URL (see TLS and reverse proxy)
docker compose up -d --build
docker compose exec -u www-data app php artisan gaeld:install   # interactive: admin user + organization
```

### Using the prebuilt image instead of building

Every release publishes a multi-arch image (`amd64` and `arm64`) to `ghcr.io/mjoe/gaeld-deploy`, so you do not need
the Docker build or the Dockerfile on the target machine. All you need are `compose.yaml`, `.env.template` and
`scripts/init.sh`:

```bash
./scripts/init.sh
echo 'GAELD_IMAGE=ghcr.io/mjoe/gaeld-deploy:3.9.0-1' >> .env    # pick a tag from the releases page
docker compose pull app
docker compose up -d --no-build
docker compose exec -u www-data app php artisan gaeld:install
```

Pin an exact tag such as `3.9.0-1` for reproducible installs. `3.9.0` follows the latest revision of that upstream
version, and `latest` follows the newest release. To update, change the tag, run `docker compose pull app` and
`docker compose up -d --no-build`; migrations run on startup. Take a backup first with `./scripts/backup.sh`
(`update.sh` is meant for building from source and does not apply to the prebuilt image).

**Known upstream bug (v3.9.0):** `gaeld:install` does not set `email_verified_at` (missing from `$fillable`),
so the admin is redirected to `/email/verify` after the first login. Workaround:

```bash
docker compose exec db sh -c 'psql -U "$POSTGRES_USER" "$POSTGRES_DB" -c "update users set email_verified_at=now() where email_verified_at is null;"'
```

## TLS and reverse proxy

The nginx inside the container speaks plain HTTP on port 8080 and has no certificates. It is the application's web
server, not an internet-facing gateway. HTTPS is provided by a TLS proxy that you run in front of it (it is not part
of this stack).

### What makes sense

Use HTTPS whenever real data is involved: Gäld handles logins and financial data, and browsers only allow passkeys
(WebAuthn) in a secure context. The most sensible setup is **one TLS proxy per host that terminates HTTPS and forwards to
`127.0.0.1:8080`**, with the container port left on localhost. Certificates and renewal belong in that proxy, not in the
application image, and one proxy can serve several applications on the same host.

| Your situation | Recommendation |
|---|---|
| Reachable from the internet under your own domain | A TLS proxy with automatic Let's Encrypt certificates on the same host. **Caddy** is the simplest choice. |
| You already run a proxy for other services (Traefik, Nginx Proxy Manager, nginx, ...) | Reuse it and add one route to port 8080. Do not add a second proxy. |
| Only reachable from your LAN or over a VPN, but you have a domain | Keep HTTPS anyway: a proxy using the DNS-01 challenge (certificates without opening ports) or an internal CA. |
| No inbound ports can be opened | A tunnel such as Cloudflare Tunnel that forwards to port 8080. |
| Quick local evaluation on one machine | Plain HTTP on `127.0.0.1:8080` (the default) is fine. Do not enter real data over an untrusted network. |

### Setup

Any TLS proxy works as long as it terminates TLS and forwards the `Host`, `X-Forwarded-For` and `X-Forwarded-Proto`
headers to `127.0.0.1:8080`. Then set in `.env` and run `docker compose up -d`:

```
APP_URL=https://gaeld.example.com
SESSION_SECURE_COOKIE=true
```

The default setup publishes the port on `127.0.0.1:8080` only, so only a TLS proxy on the same host can reach it.
For direct access from your LAN without HTTPS set `APP_BIND=0.0.0.0` (trusted networks only).

Minimal examples for a TLS proxy on the same host (not covered by the smoke test):

**Caddy** obtains and renews Let's Encrypt certificates automatically. The domain must point to the host, and ports 80
and 443 must be reachable from the internet:

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

### TLS proxy on another host

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

## Configuration

Main options in `.env` (see `.env.template` for all of them):

| Variable | Default | Purpose |
|---|---|---|
| `GAELD_IMAGE` | built from source | Use a prebuilt image such as `ghcr.io/mjoe/gaeld-deploy:3.9.0-1` instead of building |
| `GAELD_SOURCE` | `release` | `release` = release tarball (SHA256-verified), `git` = build a git ref |
| `GAELD_VERSION` | `v3.9.0` | Release tag, or git ref (`main`, branch, tag, commit) when `GAELD_SOURCE=git` |
| `INSTALL_OCR` | `false` | Install Tesseract for receipt OCR (larger image; not covered by the smoke test) |
| `APP_URL` | `http://localhost:8080` | Public URL of the instance; use the `https://` URL behind a TLS proxy |
| `SESSION_SECURE_COOKIE` | `false` | Set to `true` when the site is served over HTTPS |
| `APP_BIND` / `APP_PORT` | `127.0.0.1` / `8080` | Published address and port of the container |
| `TRUSTED_PROXIES` | `*` | Whose `X-Forwarded-*` headers are trusted; see [TLS proxy on another host](#tls-proxy-on-another-host) |
| `ALLOW_REGISTRATION` | `false` | Allow public self-registration at `/register` |
| `MAIL_*` | empty | SMTP settings (see Notes) |

## Notes

- **Architectures:** the image builds natively for `amd64` and `arm64`. Build on the target architecture
  (`docker compose build`, roughly 2-5 minutes); cross-architecture builds under emulation (QEMU) are not supported
  and can crash while compiling the PHP extensions.
- **Registration:** `/register` is blocked by default (nginx returns 404). Without this, anyone who can reach the
  instance could create their own organization. Enable it with `ALLOW_REGISTRATION=true`, then
  `docker compose up -d`. The "Create account" link on the login page stays visible but leads to a 404.
- **Mail:** without SMTP settings (`MAIL_HOST`, ...) password-reset and verification mails are lost (errors in the log).
- **Image size:** roughly 500 MB on disk (about 120 MB to download), mostly PHP, its extensions and the application's
  Composer dependencies.
- **Backups:** `backup.sh` writes files readable by the current user only and removes partial files if a step fails.
  The smoke test covers a backup/restore round trip. Test the restore regularly and keep copies off the host.
  Swiss law requires business records to be kept for 10 years.
- `docker compose down -v` deletes all data.

The exact upstream version of a running instance is stored in the image:
`docker compose exec app cat /var/www/html/.gaeld-rev` (for git builds it includes the resolved commit).
Development heads can contain unreleased migrations and breaking changes: back up first (`update.sh` does) and
expect that going back to an older version may not be possible.

## Local patches (optional)

To change something in Gäld itself, for example texts, colors or a bug fix, put unified diffs into `patches/*.patch`
and build the image yourself (`docker compose build`). The patches are applied to the upstream source during the build.
The repository ships none, `*.patch` files are ignored by git, and the published images are never patched.
See [patches/README.md](patches/README.md) for the format and the AGPL note. A broken or empty patch stops the build
with an error, and the applied patches are listed in `/var/www/html/.gaeld-rev`.

## Releases and versioning

Releases of this repository are tagged `v<upstream version>-<revision>`, for example `v3.9.0-1`:

- `3.9.0` is the Gäld release that gets built, so the upstream version is always visible.
- `-1` counts changes to this repository (Dockerfile, configuration, scripts) for the same upstream version. It starts at 1
  for every new upstream release, so fixes can be released without waiting for upstream.

Pushing a tag runs the smoke test on amd64 and arm64, builds a multi-arch image (`linux/amd64`, `linux/arm64`),
publishes it to `ghcr.io/mjoe/gaeld-deploy` with the tags `3.9.0-1` (exact), `3.9.0` (latest revision of that upstream
version) and `latest`, and creates a GitHub release. The workflow refuses a tag whose upstream part does not match
the default `GAELD_VERSION` in the repository.

Releasing a new upstream version:

```bash
./scripts/bump-upstream.sh v3.9.1     # updates the default version everywhere and checks consistency
# read the upstream release notes, run ./scripts/smoke-test.sh, commit and push
git tag v3.9.1-1 && git push origin v3.9.1-1
```

Releasing a fix for the same upstream version: commit the change and push the tag `v3.9.1-2`.

## CI

GitHub Actions runs ShellCheck, Hadolint, actionlint, a check that the upstream version is consistent across files,
and a full smoke test (build, install, login, cache tags, queue worker,
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
