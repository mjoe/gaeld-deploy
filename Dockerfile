# syntax=docker/dockerfile:1.7
# Gäld Community Edition - lean production image (overlay, no changes to the upstream source)
# GAELD_SOURCE=release: GAELD_VERSION is a release tag (tarball, SHA256-verified)
# GAELD_SOURCE=git:     GAELD_VERSION is any git ref of the upstream repo (main, branch, tag or commit)
ARG GAELD_SOURCE=release
ARG GAELD_VERSION=v3.9.0

# ---------- 1a. Fetch a release tarball and verify its checksum ----------
FROM alpine:3.24 AS source-release
ARG GAELD_VERSION
RUN apk add --no-cache curl
WORKDIR /dl
RUN set -eux; \
    base="https://github.com/Scanix/Gaeld/releases/download/${GAELD_VERSION}"; \
    curl -fsSL -o gaeld.tar.gz "$base/gaeld-ce-${GAELD_VERSION}.tar.gz"; \
    curl -fsSL -o gaeld.tar.gz.sha256 "$base/gaeld-ce-${GAELD_VERSION}.tar.gz.sha256"; \
    echo "$(cut -d' ' -f1 gaeld.tar.gz.sha256)  gaeld.tar.gz" | sha256sum -c -; \
    mkdir /src; tar xzf gaeld.tar.gz -C /src --strip-components=1; \
    echo "release ${GAELD_VERSION}" > /src/.gaeld-rev

# ---------- 1b. Fetch a git ref (BuildKit resolves the ref, so the cache follows upstream) ----------
FROM alpine:3.24 AS source-git
ARG GAELD_VERSION
RUN apk add --no-cache git
ADD --keep-git-dir=true https://github.com/Scanix/Gaeld.git#${GAELD_VERSION} /src
RUN echo "git ${GAELD_VERSION} $(git -C /src rev-parse HEAD)" > /src/.gaeld-rev && rm -rf /src/.git

FROM source-${GAELD_SOURCE} AS source

# ---------- 2. Build the frontend (platform independent, always native: Node crashes under QEMU) ----------
FROM --platform=$BUILDPLATFORM node:26-alpine AS assets
WORKDIR /app
COPY --from=source /src /app
# Node >= 25 no longer ships corepack: install the pnpm version pinned in package.json via npm
RUN npm install -g "pnpm@$(node -p "(require('./package.json').packageManager || 'pnpm@latest').split('@')[1]")"
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile && pnpm run build

# ---------- 3. PHP base (extensions) ----------
FROM php:8.5-fpm-alpine AS php-base
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions \
    && install-php-extensions pdo_pgsql bcmath gd zip intl opcache pcntl exif redis \
    && apk add --no-cache curl

# ---------- 4. Composer dependencies (production only) ----------
FROM php-base AS vendor
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
WORKDIR /app
COPY --from=source /src /app
RUN --mount=type=cache,target=/root/.composer/cache \
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --no-interaction \
      --prefer-dist --optimize-autoloader --classmap-authoritative

# ---------- 5. Runtime ----------
FROM php-base AS runtime
ARG INSTALL_OCR=false
RUN apk add --no-cache nginx supervisor \
    && if [ "$INSTALL_OCR" = "true" ]; then \
         apk add --no-cache tesseract-ocr tesseract-ocr-data-deu tesseract-ocr-data-fra tesseract-ocr-data-eng; \
       fi \
    && rm -f /etc/nginx/http.d/default.conf \
    && mkdir -p /etc/nginx/snippets

WORKDIR /var/www/html
COPY --from=vendor --chown=www-data:www-data /app /var/www/html
COPY --from=assets --chown=www-data:www-data /app/public/build /var/www/html/public/build

COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/php.ini /usr/local/etc/php/conf.d/zz-gaeld.ini
COPY docker/www.conf /usr/local/etc/php-fpm.d/zz-gaeld.conf
COPY docker/supervisord.conf /etc/supervisord.conf
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && rm -rf tests docker .github .githooks \
    && mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views storage/logs bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache

ENV APP_ENV=production APP_DEBUG=false LOG_CHANNEL=stderr
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=40s --retries=5 \
    CMD curl -fsS http://127.0.0.1:8080/up || exit 1
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisord.conf"]
