#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

STATE_DIR="${MORRO_COMMANDER_STATE_DIR:-$HOME/.morro-remote-commander}"
PID_FILE="$STATE_DIR/device.pid"
LOG_FILE="$STATE_DIR/device.log"
STOP_FILE="$STATE_DIR/stop"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PREFIX
export HOME="${HOME:-/data/data/com.termux/files/home}"
export SHELL="${SHELL:-$PREFIX/bin/bash}"
export TMPDIR="${TMPDIR:-$PREFIX/tmp}"
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PNPM_HOME:/system/bin:/system/xbin:${PATH:-}"
export LD_PRELOAD="$PREFIX/lib/libtermux-exec.so"

PACKAGE="${MORRO_COMMANDER_PACKAGE:-@wonderwhy-er/desktop-commander@0.2.52}"
AUTH_FILE="${MORRO_COMMANDER_AUTH_FILE:-$HOME/.desktop-commander-device/device.json}"

mkdir -p "$STATE_DIR"

is_live_pid() {
  local pid="${1:-}"
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

current_pid() {
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if is_live_pid "$pid"; then
    printf '%s' "$pid"
    return 0
  fi
  return 1
}

require_runtime() {
  command -v node >/dev/null 2>&1 || {
    echo "commander=BLOCKED reason=NODE_MISSING" >&2
    return 69
  }
  command -v npx >/dev/null 2>&1 || {
    echo "commander=BLOCKED reason=NPX_MISSING" >&2
    return 69
  }
}

start_device() {
  local pid launched_pid
  require_runtime

  if pid="$(current_pid 2>/dev/null)"; then
    echo "commander=RUNNING pid=$pid package=$PACKAGE"
    return 0
  fi

  if [[ ! -s "$AUTH_FILE" ]]; then
    echo "commander=PAIR_REQUIRED auth_file=$AUTH_FILE" >&2
    return 78
  fi

  rm -f "$STOP_FILE" "$PID_FILE"
  termux-wake-lock >/dev/null 2>&1 || true

  nohup npx -y "$PACKAGE" remote >>"$LOG_FILE" 2>&1 &
  launched_pid=$!
  printf '%s\n' "$launched_pid" >"$PID_FILE"

  for _ in $(seq 1 40); do
    if is_live_pid "$launched_pid"; then
      if grep -Eq 'Device ready|connected|authenticated|Remote' "$LOG_FILE" 2>/dev/null; then
        echo "commander=RUNNING pid=$launched_pid package=$PACKAGE"
        return 0
      fi
    else
      break
    fi
    sleep 0.5
  done

  if is_live_pid "$launched_pid"; then
    echo "commander=STARTED_AWAITING_READY pid=$launched_pid package=$PACKAGE"
    return 0
  fi

  echo "commander=FAILED package=$PACKAGE" >&2
  tail -n 80 "$LOG_FILE" 2>/dev/null || true
  return 1
}

stop_device() {
  local pid
  touch "$STOP_FILE"
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"

  if is_live_pid "$pid"; then
    kill -TERM "$pid" 2>/dev/null || true
    for _ in $(seq 1 40); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.25
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi

  rm -f "$PID_FILE"
  termux-wake-unlock >/dev/null 2>&1 || true
  echo "commander=STOPPED"
}

pair_device() {
  require_runtime
  echo "Starting interactive Remote Desktop Commander pairing."
  echo "Keep this terminal open until the CLI reports Device ready."
  echo "Package: $PACKAGE"
  exec npx -y "$PACKAGE" remote
}

case "${1:-status}" in
  pair)
    pair_device
    ;;
  start)
    start_device
    ;;
  stop)
    stop_device
    ;;
  restart)
    stop_device
    rm -f "$STOP_FILE"
    start_device
    ;;
  status)
    if pid="$(current_pid 2>/dev/null)"; then
      echo "commander=RUNNING pid=$pid package=$PACKAGE"
    else
      echo "commander=NOT_RUNNING package=$PACKAGE"
    fi
    if [[ -s "$AUTH_FILE" ]]; then
      echo "paired=yes auth_file=$AUTH_FILE"
    else
      echo "paired=no auth_file=$AUTH_FILE"
    fi
    echo "log=$LOG_FILE"
    tail -n 30 "$LOG_FILE" 2>/dev/null || true
    ;;
  logs)
    tail -n 200 -f "$LOG_FILE"
    ;;
  *)
    echo "usage: $0 {pair|start|stop|restart|status|logs}" >&2
    exit 64
    ;;
esac
