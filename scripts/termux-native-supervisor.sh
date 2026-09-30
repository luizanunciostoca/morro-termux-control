#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

REPO_DIR="${MORRO_AGENT_REPO_DIR:-$HOME/morro-termux-control}"
STATE_DIR="${MORRO_AGENT_STATE_DIR:-$HOME/.morro-termux-agent}"
LOG_DIR="$STATE_DIR/logs"
PID_FILE="$STATE_DIR/supervisor.pid"
STOP_FILE="$STATE_DIR/supervisor.stop"
POLL_SECONDS="${MORRO_SUPERVISOR_POLL_SECONDS:-60}"

mkdir -p "$LOG_DIR"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    log "supervisor already running pid=$old_pid"
    exit 0
  fi
fi

rm -f "$STOP_FILE"
printf '%s\n' "$$" > "$PID_FILE"

cleanup() {
  rm -f "$PID_FILE"
  log "supervisor stopped"
}
trap cleanup EXIT INT TERM

termux-wake-lock >/dev/null 2>&1 || true

log "MORRO_NATIVE_SUPERVISOR_V1 started pid=$$ poll=${POLL_SECONDS}s"

while [[ ! -f "$STOP_FILE" ]]; do
  if [[ ! -d "$REPO_DIR/.git" ]]; then
    log "repo missing: $REPO_DIR"
    sleep "$POLL_SECONDS"
    continue
  fi

  if ! gh auth status >/dev/null 2>&1; then
    log "GitHub CLI not authenticated; retrying"
    sleep "$POLL_SECONDS"
    continue
  fi

  if ! gh api user >/dev/null 2>&1; then
    log "GitHub unreachable; retrying"
    sleep "$POLL_SECONDS"
    continue
  fi

  cd "$REPO_DIR"

  bash scripts/termux-native-agentctl.sh start ||     log "agent start/check returned non-zero"

  sleep "$POLL_SECONDS"
done
