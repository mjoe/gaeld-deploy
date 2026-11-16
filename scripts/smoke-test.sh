#!/bin/sh
# Smoke test in an isolated compose project (port 18080, own volumes, removed afterwards).
# Usage: scripts/smoke-test.sh      (locally or in CI; requires docker compose v2.17+)
set -u
cd "$(dirname "$0")/.." || exit 1
PORT=18080
URL="http://localhost:$PORT"
export ENV_FILE=.env.smoke
FAILS=0
dc() { docker compose --env-file "$ENV_FILE" -p gaeld-smoke "$@"; }
cleanup() { dc down -v --remove-orphans >/dev/null 2>&1; rm -f "$ENV_FILE" /tmp/gaeld-smoke.cookies; }
trap cleanup EXIT
ok()   { echo "  ok   $1"; }
fail() { echo "  FAIL $1 (expected: $2, got: $3)"; FAILS=$((FAILS+1)); }
expect() { [ "$2" = "$3" ] && ok "$1" || fail "$1" "$2" "$3"; }
http() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

rm -f "$ENV_FILE"; ./scripts/init.sh "$ENV_FILE" >/dev/null
sed -i.bak "s|^APP_PORT=.*|APP_PORT=$PORT|; s|^APP_URL=.*|APP_URL=$URL|" "$ENV_FILE"; rm -f "$ENV_FILE.bak"
# Optional: test another upstream version, e.g. GAELD_SOURCE=git GAELD_VERSION=main scripts/smoke-test.sh
for key in GAELD_SOURCE GAELD_VERSION; do
  eval "val=\${$key:-}"
  [ -n "$val" ] && { sed -i.bak "s|^$key=.*|$key=$val|" "$ENV_FILE"; rm -f "$ENV_FILE.bak"; }
done

echo "== Start"
dc up -d --build --wait --wait-timeout 300 || { dc logs --tail 80; echo "FAIL Start"; exit 1; }

echo "Upstream source: $(dc exec -T app cat /var/www/html/.gaeld-rev 2>/dev/null)"

echo "== HTTP"
expect "/up"                200 "$(http $URL/up)"
expect "/login"             200 "$(http $URL/login)"
expect "/ redirects to login"         302 "$(http $URL/)"
expect "/register blocked" 404 "$(http $URL/register)"
expect "POST /register blocked" 404 "$(http -X POST $URL/register)"

echo "== Installation"
out=$(dc exec -T -u www-data app php artisan gaeld:install --no-interaction 2>&1)
pw=$(echo "$out" | sed -n 's/.*Admin Password[ .]*\([A-Za-z0-9]*\).*/\1/p')
[ -n "$pw" ] && ok "Installer ran, admin password received" || { fail "Installer" "password" "none"; echo "$out" | tail -15; }
dc exec -T db sh -c 'psql -q -U "$POSTGRES_USER" "$POSTGRES_DB" -c "update users set email_verified_at=now() where email_verified_at is null;"' >/dev/null
accounts=$(dc exec -T db sh -c 'psql -tA -U "$POSTGRES_USER" "$POSTGRES_DB" -c "select count(*) from accounts;"' | tr -d '\r')
[ "${accounts:-0}" -gt 0 ] && ok "Chart of accounts created ($accounts accounts)" || fail "Chart of accounts" ">0" "${accounts:-?}"

echo "== Login"
J=/tmp/gaeld-smoke.cookies; rm -f $J
curl -s -c $J -b $J -o /dev/null $URL/login
xsrf=$(awk '/XSRF-TOKEN/ {print $7}' $J | python3 -c "import sys,urllib.parse;print(urllib.parse.unquote(sys.stdin.read().strip()))")
code=$(curl -s -c $J -b $J -o /dev/null -w '%{http_code}' -H "X-XSRF-TOKEN: $xsrf" -H "X-Inertia: true" \
  -H "Content-Type: application/json" -d "{\"email\":\"admin@gaeld.local\",\"password\":\"$pw\"}" $URL/login)
expect "Login POST" 302 "$code"
for p in invoices expenses contacts; do expect "/$p after login" 200 "$(http -b $J $URL/$p)"; done

echo "== Cache (Tags), Queue, Scheduler"
dc exec -T -u www-data app sh -c 'cat > /tmp/smoke.php' <<'PHP'
<?php
require '/var/www/html/vendor/autoload.php';
$app = require '/var/www/html/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
use Illuminate\Support\Facades\Cache;
Cache::tags(['t'])->put('k', 'v', 60);
echo Cache::tags(['t'])->get('k') === 'v' ? 'tags-ok ' : 'tags-fail ';
Cache::tags(['t'])->flush();
echo Cache::tags(['t'])->get('k') === null ? 'flush-ok ' : 'flush-fail ';
@unlink('/tmp/queue-ok');
dispatch(function () { file_put_contents('/tmp/queue-ok', 'x'); });
PHP
res=$(dc exec -T -u www-data app php /tmp/smoke.php 2>&1)
echo "$res" | grep -q "tags-ok"  && ok "Cache::tags"  || fail "Cache::tags" "ok" "$res"
echo "$res" | grep -q "flush-ok" && ok "Cache flush"  || fail "Cache flush" "ok" "$res"
i=0; while [ $i -lt 20 ] && ! dc exec -T app test -f /tmp/queue-ok 2>/dev/null; do sleep 1; i=$((i+1)); done
[ $i -lt 20 ] && ok "Queue worker processed job (${i}s)" || fail "Queue worker" "job processed" "timeout"
for proc in "queue:work" "schedule:work" "php-fpm" "nginx"; do
  dc exec -T app sh -c "ps | grep -v grep | grep -q '$proc'" && ok "Process $proc is running" || fail "Process $proc" "running" "missing"
done

echo "== Restart: data persists"
dc restart app >/dev/null 2>&1
i=0; while [ $i -lt 60 ] && [ "$(http $URL/up)" != 200 ]; do sleep 2; i=$((i+1)); done
expect "/up after restart" 200 "$(http $URL/up)"
users=$(dc exec -T db sh -c 'psql -tA -U "$POSTGRES_USER" "$POSTGRES_DB" -c "select count(*) from users;"' | tr -d '\r')
expect "User preserved" 1 "$users"

echo
if [ "$FAILS" -eq 0 ]; then echo "All tests passed."; else echo "$FAILS test(s) failed."; dc logs --tail 60 app; exit 1; fi
