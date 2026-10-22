#!/usr/bin/env bash
#
# Installer for the Pinokio home-server stack.
#
# It checks the prerequisites (a container runtime with GPU support), creates
# the data directory and a .env file, builds the image, and starts the stack.
#
# Usage:
#   ./install.sh                 # install into ./config, start the stack
#   CONFIG_PATH=/srv/pinokio ./install.sh
#
# There is no hard disk-space requirement: the installer reports the free
# space in the chosen data directory and continues. (Set MIN_FREE_GB to be
# warned when less than that many gigabytes are free.)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

CONFIG_PATH="${CONFIG_PATH:-$(pwd)/config}"
# Informational only; the installer never refuses to run because of it.
MIN_FREE_GB="${MIN_FREE_GB:-100}"

# --- pick a container runtime ---------------------------------------------
RUNTIME=""
if command -v docker >/dev/null 2>&1; then
  RUNTIME=docker
elif command -v podman >/dev/null 2>&1; then
  RUNTIME=podman
fi
[ -n "$RUNTIME" ] || die "neither docker nor podman is installed"

COMPOSE=""
if [ "$RUNTIME" = docker ] && docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif [ "$RUNTIME" = docker ] && command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
elif [ "$RUNTIME" = podman ] && command -v podman-compose >/dev/null 2>&1; then
  COMPOSE="podman-compose"
fi
[ -n "$COMPOSE" ] || die "no compose command found for $RUNTIME"

info "runtime: $RUNTIME (compose: $COMPOSE)"

# --- GPU check -------------------------------------------------------------
if command -v nvidia-smi >/dev/null 2>&1; then
  info "NVIDIA GPU detected: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)"
else
  warn "nvidia-smi not found: GPU passthrough will not work (remove the deploy block in compose.yaml)"
fi

# --- data directory + free space ------------------------------------------
mkdir -p "$CONFIG_PATH"
info "data directory: $CONFIG_PATH"
if available_kb="$(df -Pk "$CONFIG_PATH" 2>/dev/null | awk 'NR==2 {print $4}')"; then
  available_gb=$(( available_kb / 1024 / 1024 ))
  echo "    free space: ${available_gb} GB"
  if [ "$available_gb" -lt "$MIN_FREE_GB" ]; then
    warn "less than ${MIN_FREE_GB} GB free (${available_gb} GB); Pinokio apps and models can use a lot of space"
  fi
fi

# --- .env ------------------------------------------------------------------
if [ ! -f .env ]; then
  info "creating .env from .env.example"
  cp .env.example .env
fi

# Require a password: without one the tunneled UI has no authentication.
if ! grep -qE '^PASSWORD=.+' .env; then
  if command -v openssl >/dev/null 2>&1; then
    generated="$(openssl rand -base64 12)"
  else
    generated="$(head -c 12 /dev/urandom | base64 | tr -d '/+=' )"
  fi
  sed -i "s|^PASSWORD=.*|PASSWORD=${generated}|" .env
  info "generated a password and wrote it to .env"
  echo "    PASSWORD=${generated}"
fi

# --- build + start ---------------------------------------------------------
info "building the image"
$COMPOSE build

info "starting the stack"
./start.sh up -d

# --- disk check on the *host*, after the volume is mounted -----------------
if [ -d "$CONFIG_PATH" ]; then
  available_gb=$(( $(df -Pk "$CONFIG_PATH" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
  info "free space in ${CONFIG_PATH}: ${available_gb} GB"
fi

info "done"
echo
echo "Read the public URL with: ./scripts/tunnel-url.sh"
echo "Sign in with the CUSTOM_USER/PASSWORD from .env."
