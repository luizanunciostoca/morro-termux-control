#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

REPO_DIR="${MORRO_CONTROL_REPO_DIR:-$HOME/morro-termux-control}"
STATE_DIR="${MORRO_COMMANDER_STATE_DIR:-$HOME/.morro-remote-commander}"
PID_FILE="$STATE_DIR/supervisor.pid"
STOP_FILE="$STATE_DIR/supervisor.stop"
LOG_FILE="$STATE_DIR/supervisor.log"
POLL_SECONDS="${MORRO_COMMANDER_SUPERVISOR_POLL_SECONDS:-60}"

mkdir -p "$STATE_DIR"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG_FILE"
}

is_live_pid() {
  local pid="${1:-}"
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if is_live_pid "$old_pid"; then
    log "commander supervisor already running pid=$old_pid"
    exit 0
  fi
fi

rm -f "$STOP_FILE"
printf '%s\n' "$$" >"$PID_FILE"

cleanup() {
  local recorded
  recorded="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ "$recorded" == "$$" ]]; then
    rm -f "$PID_FILE"
  fi
  log "commander supervisor stopped"
}
trap 'exit 0' INT TERM
trap cleanup EXIT

termux-wake-lock >/dev/null 2>&1 || true
log "MORRO_REMOTE_COMMANDER_SUPERVISOR_V1 started pid=$$ poll=${POLL_SECONDS}s"

while [[ ! -f "$STOP_FILE" ]]; do
  if [[ ! -x "$REPO_DIR/scripts/termux-remote-commanderctl.sh" ]]; then
    log "control script unavailable at $REPO_DIR"
    sleep "$POLL_SECONDS"
    continue
  fi

  if ! bash "$REPO_DIR/scripts/termux-remote-commanderctl.sh" start >>"$LOG_FILE" 2>&1; then
    log "commander start/check returned non-zero"
  fi

  sleep "$POLL_SECONDS"
done
