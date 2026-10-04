#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PREFIX
export HOME="${HOME:-/data/data/com.termux/files/home}"
export SHELL="${SHELL:-$PREFIX/bin/bash}"
export TMPDIR="${TMPDIR:-$PREFIX/tmp}"
export PATH="$PREFIX/bin:$PREFIX/bin/applets:/system/bin:/system/xbin:${PATH:-}"
export LD_PRELOAD="$PREFIX/lib/libtermux-exec.so"

REPO_DIR="${MORRO_CONTROL_REPO_DIR:-$HOME/morro-termux-control}"
SERVICE_DIR="$PREFIX/var/service/desktop-commander"
BOOT_DIR="$HOME/.termux/boot"
BOOT_HOOK="$BOOT_DIR/10-morro-remote-commander.sh"
AUTH_FILE="${MORRO_COMMANDER_AUTH_FILE:-$HOME/.desktop-commander-device/device.json}"
GLOBAL_PACKAGE="$PREFIX/lib/node_modules/@wonderwhy-er/desktop-commander"
EXPECTED_VERSION="0.2.51"
CONFIG_GUARD_SOURCE="$REPO_DIR/scripts/termux-remote-commander-config-guard.sh"
CONFIG_GUARD_DIR="$PREFIX/libexec/morro"
CONFIG_GUARD="$CONFIG_GUARD_DIR/termux-remote-commander-config-guard.sh"

mkdir -p "$SERVICE_DIR" "$BOOT_DIR" "$HOME/.local/state/desktop-commander" "$CONFIG_GUARD_DIR"

if [[ ! -f "$GLOBAL_PACKAGE/package.json" ]]; then
  echo "direct_access=BLOCKED reason=GLOBAL_COMMANDER_MISSING" >&2
  exit 69
fi

ACTUAL_VERSION="$(node -p "require('$GLOBAL_PACKAGE/package.json').version")"
if [[ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "direct_access=BLOCKED reason=UNVALIDATED_COMMANDER_VERSION actual=$ACTUAL_VERSION expected=$EXPECTED_VERSION" >&2
  exit 78
fi

if [[ ! -x "$CONFIG_GUARD_SOURCE" ]]; then
  echo "direct_access=BLOCKED reason=CONFIG_GUARD_SOURCE_MISSING path=$CONFIG_GUARD_SOURCE" >&2
  exit 69
fi
install -m 700 "$CONFIG_GUARD_SOURCE" "$CONFIG_GUARD"
"$CONFIG_GUARD"

cat >"$SERVICE_DIR/run" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export SHELL="$PREFIX/bin/bash"
export TMPDIR="$PREFIX/tmp"
export PATH="$PREFIX/bin:$PREFIX/bin/applets:/system/bin:/system/xbin"
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
export LD_PRELOAD="$PREFIX/lib/libtermux-exec.so"
export TERM=xterm-256color
export GIT_TERMINAL_PROMPT=0
export TURBO_TELEMETRY_DISABLED=1
mkdir -p "$TMPDIR" "$HOME/.local/state/desktop-commander"
CONFIG_GUARD="$PREFIX/libexec/morro/termux-remote-commander-config-guard.sh"
if [ ! -x "$CONFIG_GUARD" ]; then
  echo "commander=BLOCKED reason=CONFIG_GUARD_MISSING path=$CONFIG_GUARD" >&2
  exit 69
fi
"$CONFIG_GUARD" >>"$HOME/.local/state/desktop-commander/remote.log" 2>&1
cd "$HOME"
exec "$PREFIX/bin/node" "$PREFIX/lib/node_modules/@wonderwhy-er/desktop-commander/dist/index.js" remote >>"$HOME/.local/state/desktop-commander/remote.log" 2>&1
EOF
chmod 700 "$SERVICE_DIR/run"

cat >"$BOOT_HOOK" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export SHELL="$PREFIX/bin/bash"
export TMPDIR="$PREFIX/tmp"
export PATH="$PREFIX/bin:$PREFIX/bin/applets:/system/bin:/system/xbin:$PATH"
termux-wake-lock >/dev/null 2>&1 || true
if [[ -f "$PREFIX/etc/profile.d/start-services.sh" ]]; then
  . "$PREFIX/etc/profile.d/start-services.sh"
fi
rm -f "$PREFIX/var/service/desktop-commander/down"
sv up "$PREFIX/var/service/desktop-commander" 2>/dev/null || true
EOF
chmod 700 "$BOOT_HOOK"

STATE_DIR="$HOME/.morro-remote-commander"
if [[ -f "$STATE_DIR/supervisor.pid" ]]; then
  p="$(cat "$STATE_DIR/supervisor.pid" 2>/dev/null || true)"
  [[ "$p" =~ ^[0-9]+$ ]] && kill -TERM "$p" 2>/dev/null || true
fi
rm -f "$STATE_DIR/supervisor.pid" "$STATE_DIR/device.pid" "$STATE_DIR/supervisor.stop"

if [[ ! -s "$AUTH_FILE" ]]; then
  touch "$SERVICE_DIR/down"
  echo "direct_access=PAIR_REQUIRED"
  echo "next=bash $REPO_DIR/scripts/termux-remote-commanderctl.sh pair"
  exit 0
fi

rm -f "$SERVICE_DIR/down"
if [[ -f "$PREFIX/etc/profile.d/start-services.sh" ]]; then
  . "$PREFIX/etc/profile.d/start-services.sh"
fi
sv up "$SERVICE_DIR"
sleep 1
echo "direct_access=INSTALLED_AND_ACTIVATED"
echo "commander_version=$ACTUAL_VERSION"
sv status "$SERVICE_DIR"
