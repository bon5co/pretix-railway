#!/bin/bash
# Railway boot for Pretix.
#
# Refuses to start without strong secrets and the database and Redis settings, points nginx at the injected PORT, hands the /data
# volume to pretixuser, migrates (retrying, because Railway's generate step starts three deployments against one database),
# replaces the default admin@localhost login with ADMIN_EMAIL / ADMIN_PASSWORD, creates an organizer and API token, and only then
# starts nginx, gunicorn and the task worker under supervisord, so the default login is never reachable.
set -u
fail() { echo "[railway] $1" >&2; exit 1; }
[ "${1:-}" = "all" ] || exec /usr/local/bin/pretix "$@"

[ -n "${ADMIN_PASSWORD:-}" ] || fail "ADMIN_PASSWORD is not set; refusing to start a ticket shop with no admin login"
[ "${#ADMIN_PASSWORD}" -ge 12 ] || fail "ADMIN_PASSWORD must be at least 12 characters"
[ "${ADMIN_PASSWORD}" != "admin" ] || fail "ADMIN_PASSWORD must not be the upstream default"
[ -n "${ADMIN_EMAIL:-}" ] || fail "ADMIN_EMAIL is not set"
ADMIN_API_KEY="${ADMIN_API_KEY:-}"
[ "${#ADMIN_API_KEY}" -ge 32 ] || fail "ADMIN_API_KEY must be set and at least 32 characters"
for v in HOST NAME USER PASSWORD; do
  eval "val=\${PRETIX_DATABASE_$v:-}"
  [ -n "$val" ] || fail "PRETIX_DATABASE_$v is not set"
done
[ -n "${PRETIX_REDIS_LOCATION:-}" ] || fail "PRETIX_REDIS_LOCATION is not set"
[ -n "${PRETIX_CELERY_BROKER:-}" ] || fail "PRETIX_CELERY_BROKER is not set"
[ -n "${PRETIX_CELERY_BACKEND:-}" ] || fail "PRETIX_CELERY_BACKEND is not set"
if [ -z "${PRETIX_PRETIX_URL:-}" ]; then
  [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ] || fail "neither PRETIX_PRETIX_URL nor RAILWAY_PUBLIC_DOMAIN is set"
  export PRETIX_PRETIX_URL="https://$RAILWAY_PUBLIC_DOMAIN"
fi
case "${PORT:=8080}" in ''|*[!0-9]*) fail "PORT must be a number, got '$PORT'";; esac
export PORT

echo "[railway] Pretix on :$PORT as $PRETIX_PRETIX_URL, postgres $PRETIX_DATABASE_HOST, /data owner before=$(stat -c %u:%g /data)"

# nginx listens on 80 upstream; Railway's healthcheck and edge dial the injected PORT
sed -i "s/listen 80 /listen $PORT /; s/listen \[::\]:80 /listen [::]:$PORT /" /etc/nginx/nginx.conf
grep -q "listen $PORT " /etc/nginx/nginx.conf || fail "could not point nginx at $PORT"

# a volume mounts owned by root; pretixuser (uid 15371) must be able to write
mkdir -p /data/logs /data/media
chown -R pretixuser:pretixuser /data || fail "could not hand /data to pretixuser"
echo "[railway] /data owner after=$(stat -c %u:%g /data)"

run_as_pretix() {
  setpriv --reuid=pretixuser --regid=pretixuser --init-groups env HOME=/pretix DATA_DIR=/data/ "$@"
}

cd /pretix/src || fail "no /pretix/src"
n=0
until run_as_pretix python3 -m pretix migrate --noinput; do
  n=$((n + 1)); [ "$n" -lt 6 ] || fail "migrate failed $n times"
  echo "[railway] migrate failed (try $n), retrying" >&2; sleep 10
done

n=0
until run_as_pretix python3 -m pretix shell < /railway-bootstrap.py; do
  n=$((n + 1)); [ "$n" -lt 6 ] || fail "bootstrap failed $n times"
  echo "[railway] bootstrap failed (try $n), retrying" >&2; sleep 10
done

# the stock entrypoint would run `sudo -E supervisord`; this process is already root and the programs drop to pretixuser themselves
export AUTOMIGRATE=skip
exec /usr/bin/supervisord -n -c /etc/supervisord.all.conf
