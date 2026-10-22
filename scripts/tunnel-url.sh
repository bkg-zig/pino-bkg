#!/usr/bin/env bash
# Print the current public bore URL for the Pinokio stack.
#
# Waits up to WAIT seconds (default 30) for the tunnel container to report its
# endpoint.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  logs() { docker logs pinokio-bore 2>&1; }
else
  name=pinokio-bore
  if [ "$(id -u)" -ne 0 ]; then
    logs() { sudo -n podman logs "$name" 2>&1; }
  else
    logs() { podman logs "$name" 2>&1; }
  fi
fi

wait="${WAIT:-30}"
hostport=""
for _ in $(seq 1 "$wait"); do
  hostport="$(logs | sed -n 's/.*listening at //p' | tail -n 1 || true)"
  [ -n "$hostport" ] && break
  sleep 1
done

if [ -z "$hostport" ]; then
  echo "No tunnel URL yet. Is the stack running?  ./start.sh" >&2
  exit 1
fi

# bore prints host:port; the web UI is TLS-terminated by bore when it uses the
# "https://" listener. Default to https because the public endpoint is HTTPS.
echo "https://${hostport}"
