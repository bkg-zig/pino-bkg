#!/usr/bin/env bash
#
# Bring the Pinokio home-server stack up or down.
#
# Wraps docker compose / podman-compose and hides the PASSWORD that the
# compose tool echoes on its command line.
#
# Usage:
#   ./start.sh              # start detached, then print the public URL
#   ./start.sh up -d
#   ./start.sh down
#   ./start.sh restart
#   ./start.sh logs -f bore
#   ./start.sh tunnel       # print the current public URL
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ -f .env ] || die ".env is missing; run ./install.sh (or cp .env.example .env)"

# --- pick a compose command (same logic as install.sh) ---------------------
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
elif command -v podman-compose >/dev/null 2>&1; then
  # podman-compose 1.0.6 needs --in-pod= to avoid wrapping services in a pod.
  COMPOSE=(podman-compose -f compose.yaml --in-pod=)
else
  die "no compose command found"
fi

if [ $# -eq 0 ]; then
  set -- up -d
fi

case "$1" in
  tunnel)
    exec ./scripts/tunnel-url.sh
    ;;
  up|start)
    [ $# -eq 1 ] && set -- up -d
    status=0
    "${COMPOSE[@]}" "$@" 2>&1 | sed -E 's/(PASSWORD=)[^ ]+/\1***/g' || status=$?
    [ "$status" -eq 0 ] || printf 'warning: compose exited with status %s\n' "$status" >&2
    printf '\nwaiting for the bore tunnel...\n'
    ./scripts/tunnel-url.sh || \
      printf 'tunnel is still starting; run ./scripts/tunnel-url.sh in a moment\n'
    ;;
  *)
    "${COMPOSE[@]}" "$@"
    ;;
esac
