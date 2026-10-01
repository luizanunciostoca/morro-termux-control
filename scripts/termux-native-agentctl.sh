#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

STATE_DIR="${MORRO_AGENT_STATE_DIR:-$HOME/.morro-termux-agent}"
REPO_DIR="${MORRO_AGENT_REPO_DIR:-$HOME/morro-termux-control}"
PID_FILE="$STATE_DIR/agent.pid"
LOCK_DIR="$STATE_DIR/daemon.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"
STOP_FILE="$STATE_DIR/stop"
LOG_FILE="$STATE_DIR/logs/agent.log"

mkdir -p "$STATE_DIR/logs"

is_live_pid() {
  local pid="${1:-}"
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

live_agent_pid() {
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if is_live_pid "$pid"; then
    printf '%s' "$pid"
    return 0
  fi

  pid="$(cat "$LOCK_PID_FILE" 2>/dev/null || true)"
  if is_live_pid "$pid"; then
    printf '%s\n' "$pid" > "$PID_FILE"
    printf '%s' "$pid"
    return 0
  fi

  return 1
}

sync_main() {
  cd "$REPO_DIR"
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "agent=SYNC_BLOCKED reason=TRACKED_WORKTREE_DIRTY" >&2
    return 1
  fi

  git fetch origin main
  if [[ "$(git branch --show-current)" != "main" ]]; then
    git switch main
  fi
  git merge --ff-only origin/main
}

start_agent() {
  local pid launched_pid
  if pid="$(live_agent_pid 2>/dev/null)"; then
    echo "agent=RUNNING pid=$pid"
    return 0
  fi

  sync_main
  rm -f "$STOP_FILE"
  rm -f "$PID_FILE"
  if [[ -d "$LOCK_DIR" ]]; then
    pid="$(cat "$LOCK_PID_FILE" 2>/dev/null || true)"
    if ! is_live_pid "$pid"; then
      rm -f "$LOCK_PID_FILE"
      rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
  fi

  cd "$REPO_DIR"
  nohup bash scripts/termux-native-agent.sh daemon >> "$LOG_FILE" 2>&1 &
  launched_pid=$!

  for _ in $(seq 1 40); do
    if ! kill -0 "$launched_pid" 2>/dev/null; then
      break
    fi
    if pid="$(live_agent_pid 2>/dev/null)" && [[ "$pid" == "$launched_pid" ]]; then
      echo "agent=RUNNING pid=$pid"
      return 0
    fi
    sleep 0.25
  done

  echo "agent=FAILED launched_pid=$launched_pid" >&2
  tail -n 80 "$LOG_FILE" || true
  return 1
}

stop_agent() {
  local pid
  touch "$STOP_FILE"
  pid="$(live_agent_pid 2>/dev/null || true)"
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

  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if ! is_live_pid "$pid"; then
    rm -f "$PID_FILE"
  fi
  pid="$(cat "$LOCK_PID_FILE" 2>/dev/null || true)"
  if ! is_live_pid "$pid"; then
    rm -f "$LOCK_PID_FILE"
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
  termux-wake-unlock >/dev/null 2>&1 || true
  echo "agent=STOPPED"
}

recover_agent() {
  local pid
  stop_agent

  # Break-glass cleanup for legacy/corrupt PID files created by older builds.
  pkill -TERM -f '[t]ermux-native-agent.sh daemon' 2>/dev/null || true
  sleep 1
  pkill -KILL -f '[t]ermux-native-agent.sh daemon' 2>/dev/null || true

  pid="$(cat "$LOCK_PID_FILE" 2>/dev/null || true)"
  if ! is_live_pid "$pid"; then
    rm -f "$LOCK_PID_FILE"
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
  rm -f "$PID_FILE" "$STOP_FILE"

  start_agent
}

case "${1:-status}" in
  start)
    start_agent
    ;;
  stop)
    stop_agent
    ;;
  restart)
    stop_agent
    start_agent
    ;;
  recover)
    recover_agent
    ;;
  status)
    if pid="$(live_agent_pid 2>/dev/null)"; then
      echo "agent=RUNNING pid=$pid"
    else
      echo "agent=NOT_RUNNING"
    fi
    echo "repo=$REPO_DIR"
    echo "log=$LOG_FILE"
    echo "pid_file=$(cat "$PID_FILE" 2>/dev/null || true)"
    echo "lock_pid=$(cat "$LOCK_PID_FILE" 2>/dev/null || true)"
    tail -n 20 "$LOG_FILE" 2>/dev/null || true
    ;;
  once)
    cd "$REPO_DIR"
    exec bash scripts/termux-native-agent.sh once
    ;;
  logs)
    tail -n 200 -f "$LOG_FILE"
    ;;
  *)
    echo "usage: $0 {start|stop|restart|recover|status|once|logs}" >&2
    exit 64
    ;;
esac
