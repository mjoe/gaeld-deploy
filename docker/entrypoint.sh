#!/bin/sh
set -e
cd /var/www/html || exit 1

if [ -z "$APP_KEY" ] || [ "$APP_KEY" = "base64:" ]; then
    echo "ERROR: APP_KEY is not set. Run ./scripts/init.sh first." >&2
    exit 1
fi

# The volume may be empty (first start) or need new subdirectories (after an update)
mkdir -p storage/app/public storage/framework/cache storage/framework/sessions \
         storage/framework/views storage/logs bootstrap/cache
chown -R www-data:www-data storage bootstrap/cache

# Block public self-registration (it creates new organizations) unless explicitly allowed
if [ "${ALLOW_REGISTRATION:-false}" = "true" ]; then
    : > /etc/nginx/snippets/registration.conf
else
    echo 'location = /register { return 404; }' > /etc/nginx/snippets/registration.conf
fi

as_www() { su -s /bin/sh www-data -c "$*"; }

as_www php artisan storage:link --force >/dev/null 2>&1 || true

if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
    as_www php artisan migrate --force
fi

as_www "php artisan config:cache && php artisan route:cache && php artisan view:cache && php artisan event:cache"

exec "$@"
