#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

REPO_DIR="${MORRO_CONTROL_REPO_DIR:-$HOME/morro-termux-control}"
BOOT_DIR="$HOME/.termux/boot"
BOOT_HOOK="$BOOT_DIR/10-morro-remote-commander.sh"
LEGACY="$BOOT_DIR/00-morro-remote.sh"
LEGACY_DISABLED="$BOOT_DIR/00-morro-remote.sh.disabled"
STATE_DIR="${MORRO_COMMANDER_STATE_DIR:-$HOME/.morro-remote-commander}"
SUP_PID_FILE="$STATE_DIR/supervisor.pid"

mkdir -p "$BOOT_DIR" "$STATE_DIR"

if [[ -f "$LEGACY" ]]; then
  mv "$LEGACY" "$LEGACY_DISABLED"
  chmod 600 "$LEGACY_DISABLED"
fi

cat >"$BOOT_HOOK" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export SHELL="\$PREFIX/bin/bash"
export TMPDIR="\$PREFIX/tmp"
export PATH="\$PREFIX/bin:\$PREFIX/bin/applets:/system/bin:/system/xbin:\$PATH"

sleep 12
termux-wake-lock >/dev/null 2>&1 || true

STATE_DIR="\$HOME/.morro-remote-commander"
mkdir -p "\$STATE_DIR"
nohup bash "\$HOME/morro-termux-control/scripts/termux-remote-commander-supervisor.sh" \
  >>"\$STATE_DIR/boot.log" 2>&1 &
EOF

chmod 700 "$BOOT_HOOK"
chmod 700 "$REPO_DIR/scripts/termux-remote-commanderctl.sh"
chmod 700 "$REPO_DIR/scripts/termux-remote-commander-supervisor.sh"

if [[ -f "$SUP_PID_FILE" ]]; then
  pid="$(cat "$SUP_PID_FILE" 2>/dev/null || true)"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    echo "direct_access=SUPERVISOR_ALREADY_RUNNING pid=$pid"
    echo "boot_hook=$BOOT_HOOK"
    exit 0
  fi
fi

nohup bash "$REPO_DIR/scripts/termux-remote-commander-supervisor.sh" \
  >>"$STATE_DIR/boot.log" 2>&1 &

sleep 1
echo "direct_access=INSTALLED"
echo "boot_hook=$BOOT_HOOK"
echo "next=bash $REPO_DIR/scripts/termux-remote-commanderctl.sh pair"
