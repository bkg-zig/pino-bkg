#!/bin/bash
# Install the nginx reverse proxy for Pinokio's own web UI (port 42000).
#
# Runs from /custom-cont-init.d, i.e. during init-mods-end and therefore
# before the base image's init-nginx / svc-nginx. All we have to do is make
# sure the server block is in /etc/nginx/conf.d before nginx starts, and that
# the basic auth file exists.
#
# The base image's init-nginx writes /etc/nginx/.htpasswd from CUSTOM_USER /
# PASSWORD when PASSWORD is set. We create it here too so the UI proxy works
# even if that step is skipped, and disable auth in the server block if there
# is no password at all (matching the desktop behaviour).
set -euo pipefail

SRC=/etc/pinokio/ui-proxy.conf
DST=/etc/nginx/conf.d/10-pinokio-ui.conf

if [ ! -f "$SRC" ]; then
  echo "[pinokio-ui] $SRC is missing; skipping UI proxy setup" >&2
  exit 0
fi

CUSER="${CUSTOM_USER:-abc}"

if [ -n "${PASSWORD:-}" ]; then
  if [ ! -s /etc/nginx/.htpasswd ]; then
    printf '%s:%s\n' "$CUSER" "$(openssl passwd -apr1 "$PASSWORD")" > /etc/nginx/.htpasswd
  fi
  cp "$SRC" "$DST"
  echo "[pinokio-ui] UI proxy enabled on port 3002 with basic auth for '${CUSER}'"
else
  # No password: drop the auth directives so the proxy still starts.
  sed -e '/auth_basic /d' "$SRC" > "$DST"
  echo "[pinokio-ui] WARNING: PASSWORD is not set, the tunneled UI has no authentication" >&2
fi
