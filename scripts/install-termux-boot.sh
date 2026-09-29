#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

BOOT_DIR="$HOME/.termux/boot"
STATE_DIR="$HOME/.morro-termux-runner"
BOOT_SCRIPT="$BOOT_DIR/10-morro-github-runner"
LOG_FILE="$STATE_DIR/boot.log"
PID_FILE="$STATE_DIR/proot.pid"

command -v proot-distro >/dev/null 2>&1 || {
  echo "proot-distro not found. Run: pkg install proot-distro" >&2
  exit 69
}

mkdir -p "$BOOT_DIR" "$STATE_DIR"

cat > "$BOOT_SCRIPT" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -u

STATE_DIR="$HOME/.morro-termux-runner"
LOG_FILE="$STATE_DIR/boot.log"
PID_FILE="$STATE_DIR/proot.pid"

mkdir -p "$STATE_DIR"

termux-wake-lock >/dev/null 2>&1 || true

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    exit 0
  fi
fi

nohup proot-distro login debian --   bash -lc '
    export RUNNER_ALLOW_RUNASROOT=1
    cd /root/morro-actions-runner
    rm -f .morro-stop
    exec ./runner-loop.sh
  ' >>"$LOG_FILE" 2>&1 &

echo $! > "$PID_FILE"
EOF

chmod 700 "$BOOT_SCRIPT"

echo "Installed: $BOOT_SCRIPT"
echo "State:     $STATE_DIR"
echo
echo "IMPORTANT:"
echo "1. Install/open Termux:Boot once."
echo "2. Set Android battery mode for Termux and Termux:Boot to Unrestricted."
echo "3. On Samsung, add both apps to Never sleeping apps."
echo
echo "You can start it now without rebooting:"
echo "  $BOOT_SCRIPT"
