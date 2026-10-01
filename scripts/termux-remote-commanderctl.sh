#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PREFIX
export HOME="${HOME:-/data/data/com.termux/files/home}"
export SHELL="${SHELL:-$PREFIX/bin/bash}"
export TMPDIR="${TMPDIR:-$PREFIX/tmp}"
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PNPM_HOME:/system/bin:/system/xbin:${PATH:-}"
export LD_PRELOAD="$PREFIX/lib/libtermux-exec.so"

SERVICE_DIR="$PREFIX/var/service/desktop-commander"
AUTH_FILE="${MORRO_COMMANDER_AUTH_FILE:-$HOME/.desktop-commander-device/device.json}"
PACKAGE="${MORRO_COMMANDER_PACKAGE:-@wonderwhy-er/desktop-commander@0.2.51}"

require_runtime() {
  command -v node >/dev/null 2>&1 || { echo "commander=BLOCKED reason=NODE_MISSING" >&2; return 69; }
  command -v npx >/dev/null 2>&1 || { echo "commander=BLOCKED reason=NPX_MISSING" >&2; return 69; }
  command -v sv >/dev/null 2>&1 || { echo "commander=BLOCKED reason=TERMUX_SERVICES_MISSING" >&2; return 69; }
}

start_service() {
  require_runtime
  if [[ ! -s "$AUTH_FILE" ]]; then
    echo "commander=PAIR_REQUIRED auth_file=$AUTH_FILE" >&2
    return 78
  fi
  rm -f "$SERVICE_DIR/down"
  sv up "$SERVICE_DIR"
  sleep 1
  sv status "$SERVICE_DIR"
}

stop_service() {
  mkdir -p "$SERVICE_DIR"
  touch "$SERVICE_DIR/down"
  sv down "$SERVICE_DIR" 2>/dev/null || true
  echo "commander=STOPPED"
}

pair_device() {
  require_runtime
  stop_service >/dev/null 2>&1 || true
  echo "Starting interactive Remote Desktop Commander pairing."
  echo "Keep this terminal open until the CLI reports Device ready."
  exec npx -y "$PACKAGE" remote
}

case "${1:-status}" in
  pair) pair_device ;;
  start) start_service ;;
  stop) stop_service ;;
  restart)
    stop_service
    rm -f "$SERVICE_DIR/down"
    start_service
    ;;
  status)
    if [[ -s "$AUTH_FILE" ]]; then
      echo "paired=yes auth_file=$AUTH_FILE"
    else
      echo "paired=no auth_file=$AUTH_FILE"
    fi
    sv status "$SERVICE_DIR" 2>&1 || true
    ;;
  logs)
    tail -n 200 -f "$HOME/.local/state/desktop-commander/remote.log"
    ;;
  *)
    echo "usage: $0 {pair|start|stop|restart|status|logs}" >&2
    exit 64
    ;;
esac
