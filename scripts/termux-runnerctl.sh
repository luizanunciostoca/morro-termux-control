#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

STATE_DIR="$HOME/.morro-termux-runner"
BOOT_SCRIPT="$HOME/.termux/boot/10-morro-github-runner"
PID_FILE="$STATE_DIR/proot.pid"
LOG_FILE="$STATE_DIR/boot.log"

cmd="${1:-status}"

case "$cmd" in
  start)
    [[ -x "$BOOT_SCRIPT" ]] || {
      echo "Boot script not installed: $BOOT_SCRIPT" >&2
      exit 69
    }
    "$BOOT_SCRIPT"
    ;;

  stop)
    proot-distro login debian -- bash -lc       'touch /root/morro-actions-runner/.morro-stop; pkill -TERM -f "Runner.Listener" 2>/dev/null || true' || true

    if [[ -f "$PID_FILE" ]]; then
      pid="$(cat "$PID_FILE" 2>/dev/null || true)"
      [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
      rm -f "$PID_FILE"
    fi

    termux-wake-unlock >/dev/null 2>&1 || true
    echo "Runner stop requested."
    ;;

  restart)
    "$0" stop
    sleep 2
    "$0" start
    ;;

  status)
    echo "=== Termux side ==="
    if [[ -f "$PID_FILE" ]]; then
      pid="$(cat "$PID_FILE" 2>/dev/null || true)"
      if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        echo "proot_wrapper=RUNNING pid=$pid"
      else
        echo "proot_wrapper=STALE"
      fi
    else
      echo "proot_wrapper=NO_PID"
    fi

    echo
    echo "=== Debian runner ==="
    proot-distro login debian -- bash -lc '
      cd /root/morro-actions-runner 2>/dev/null || {
        echo "runner=NOT_INSTALLED"
        exit 0
      }
      if pgrep -af "Runner.Listener" >/dev/null 2>&1; then
        echo "runner=RUNNING"
        pgrep -af "Runner.Listener" || true
      else
        echo "runner=NOT_RUNNING"
      fi
      [[ -f .runner ]] && echo "registration=CONFIGURED" || echo "registration=NOT_CONFIGURED"
    '

    echo
    echo "=== Last log lines ==="
    tail -n 30 "$LOG_FILE" 2>/dev/null || true
    ;;

  logs)
    tail -n 200 -f "$LOG_FILE"
    ;;

  *)
    echo "usage: $0 {start|stop|restart|status|logs}" >&2
    exit 64
    ;;
esac
