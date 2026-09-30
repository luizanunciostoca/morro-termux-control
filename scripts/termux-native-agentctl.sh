#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

STATE_DIR="${MORRO_AGENT_STATE_DIR:-$HOME/.morro-termux-agent}"
REPO_DIR="${MORRO_AGENT_REPO_DIR:-$HOME/morro-termux-control}"
PID_FILE="$STATE_DIR/agent.pid"
STOP_FILE="$STATE_DIR/stop"
LOG_FILE="$STATE_DIR/logs/agent.log"

mkdir -p "$STATE_DIR/logs"

start_agent() {
  if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "agent=RUNNING pid=$pid"
      return 0
    fi
  fi

  rm -f "$STOP_FILE"
  cd "$REPO_DIR"
  git pull --ff-only >/dev/null 2>&1 || true
  nohup bash scripts/termux-native-agent.sh daemon >> "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  sleep 2

  pid="$(cat "$PID_FILE")"
  if kill -0 "$pid" 2>/dev/null; then
    echo "agent=RUNNING pid=$pid"
  else
    echo "agent=FAILED"
    tail -n 80 "$LOG_FILE" || true
    exit 1
  fi
}

case "${1:-status}" in
  start)
    start_agent
    ;;
  stop)
    touch "$STOP_FILE"
    if [[ -f "$PID_FILE" ]]; then
      pid="$(cat "$PID_FILE" 2>/dev/null || true)"
      [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null || true
    fi
    termux-wake-unlock >/dev/null 2>&1 || true
    echo "agent=STOP_REQUESTED"
    ;;
  restart)
    bash "$0" stop
    sleep 2
    start_agent
    ;;
  status)
    if [[ -f "$PID_FILE" ]]; then
      pid="$(cat "$PID_FILE" 2>/dev/null || true)"
      if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        echo "agent=RUNNING pid=$pid"
      else
        echo "agent=STALE"
      fi
    else
      echo "agent=NOT_RUNNING"
    fi
    echo "repo=$REPO_DIR"
    echo "log=$LOG_FILE"
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
    echo "usage: $0 {start|stop|restart|status|once|logs}" >&2
    exit 64
    ;;
esac
