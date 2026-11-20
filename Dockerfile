# Pretix wrapper for Railway. The official image runs nginx, gunicorn and celery under supervisord and listens on 80 as the
# non-root pretixuser, and its first migration creates a superuser admin@localhost with the password "admin". Railway's healthcheck
# and edge dial the injected PORT and mount volumes owned by root, so the wrapper runs as root only long enough to point nginx at
# $PORT and hand /data to pretixuser, then migrates, replaces that default login with ADMIN_EMAIL / ADMIN_PASSWORD, creates an
# organizer with an API token from ADMIN_API_KEY, and only then starts the web server, so the default login is never reachable.
# Literals a deployer should never have to type are baked in here as ENV.
#
# The upstream image is FLATTENED into a single layer (FROM scratch + COPY --from), because Railway ignores OCI whiteouts and a
# plain FROM revives files an earlier layer wrote and a later layer deleted.
# upstream: pretix/pretix
FROM pretix/standalone:2026.9.2@sha256:441c1261721979c03895a1af93b39ac5a5a9805d8e56b68222cf788391525fc3 AS upstream

# upstream: none flattened copy of the pinned upstream stage above
FROM scratch
COPY --from=upstream / /

COPY --chmod=0755 boot.sh /railway-boot.sh
COPY --chmod=0644 bootstrap.py /railway-bootstrap.py

# upstream's own ENV (a scratch base inherits none), then the wrapper's
ENV PATH=/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHON_VERSION=3.13.18 \
    DJANGO_SETTINGS_MODULE=production_settings \
    PRETIX_DATABASE_BACKEND=postgresql \
    PRETIX_DATABASE_PORT=5432 \
    PRETIX_REDIS_SESSIONS=true \
    PRETIX_PRETIX_TRUST_X_FORWARDED_FOR=true \
    PRETIX_PRETIX_TRUST_X_FORWARDED_PROTO=true \
    PRETIX_PRETIX_TRUST_X_FORWARDED_HOST=true \
    PRETIX_PRETIX_REGISTRATION=false \
    PRETIX_PRETIX_INSTANCE_NAME=Pretix \
    AUTOMIGRATE=skip

WORKDIR /pretix/src
USER root
VOLUME ["/data", "/etc/pretix"]
EXPOSE 8080
ENTRYPOINT ["/railway-boot.sh"]
CMD ["all"]
