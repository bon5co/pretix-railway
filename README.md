# pretix-railway

Wrapper image for [Pretix](https://github.com/pretix/pretix) (ticketing and event shop, Apache-2.0) on Railway.

It runs the official `pretix/standalone` image, pinned by digest, with nginx pointed at Railway's injected `PORT`, `/data` handed
to the service user, migrations retried, the default `admin@localhost` login replaced by `ADMIN_EMAIL` / `ADMIN_PASSWORD`, public
registration closed, and an organizer with an API token created from `ADMIN_API_KEY` before the web server starts.
