#!/bin/bash
# Single-instance launcher for the Pinokio desktop app.
#
# Replaces the stock /opt/Pinokio/pinokio wrapper (see wrapped-pinokio).
#
# Two deliberate choices:
#
#  * GPU acceleration stays enabled. There is no --disable-gpu and no
#    ELECTRON_DISABLE_GPU here; the bind-mounted app.asar has had its stock
#    app.disableHardwareAcceleration() call neutralised as well.
#
#  * Pinokio is forced into "full" desktop mode. The stock Linux build
#    defaults to "background" (tray-only) mode, which opens a hidden window,
#    so the streamed desktop would look empty.
#
# The launcher is idempotent: autostart, the application menu and the desktop
# entry all call it, but only the first invocation actually starts the app.
set -u

export HOME="${HOME:-/config}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/config/.XDG}"
export DISPLAY="${DISPLAY:-:1}"
unset DBUS_SESSION_BUS_ADDRESS

# Force full (visible desktop) mode. pinokiod reads config.json very early, so
# fix it up here rather than relying on the app's own startup path.
CONFIG_JSON="$HOME/.pinokio/config.json"
if command -v python3 >/dev/null 2>&1 && [ -f "$CONFIG_JSON" ]; then
  python3 - "$CONFIG_JSON" <<'PY' || true
import json, sys
p = sys.argv[1]
try:
    with open(p) as f:
        d = json.load(f)
except Exception:
    d = {}
d["mode"] = "full"
with open(p, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY
fi

# Single instance. The lock is held for the lifetime of the process so that a
# concurrent launch cannot start a second copy. The lock file is created
# world-writable so it works regardless of which service user gets here first.
LOCK=/tmp/pinokio-start.lock
: > "$LOCK" 2>/dev/null || true
chmod 0666 "$LOCK" 2>/dev/null || true
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "another pinokio launcher holds the lock; exiting" >&2
  exit 0
fi

if pgrep -x pinokio-bin >/dev/null 2>&1; then
  exit 0
fi

exec /opt/Pinokio/pinokio-bin \
  --no-sandbox \
  --ozone-platform=x11 \
  --start-maximized \
  "$@"
