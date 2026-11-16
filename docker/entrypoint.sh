#!/bin/sh
set -e
cd /var/www/html

if [ -z "$APP_KEY" ] || [ "$APP_KEY" = "base64:" ]; then
    echo "FEHLER: APP_KEY ist nicht gesetzt. Zuerst ./scripts/init.sh ausführen." >&2
    exit 1
fi

# Volume kann leer sein (erster Start) oder neue Unterordner brauchen (Update)
mkdir -p storage/app/public storage/framework/cache storage/framework/sessions \
         storage/framework/views storage/logs bootstrap/cache
chown -R www-data:www-data storage bootstrap/cache

# Öffentliche Registrierung (legt neue Organisationen an) standardmässig sperren
if [ "${ALLOW_REGISTRATION:-false}" = "true" ]; then
    : > /etc/nginx/snippets/registration.conf
else
    echo 'location ^~ /register { return 404; }' > /etc/nginx/snippets/registration.conf
fi

as_www() { su -s /bin/sh www-data -c "$*"; }

as_www php artisan storage:link --force >/dev/null 2>&1 || true

if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
    as_www php artisan migrate --force
fi

as_www "php artisan config:cache && php artisan route:cache && php artisan view:cache && php artisan event:cache"

exec "$@"
