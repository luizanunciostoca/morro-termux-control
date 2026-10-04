#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="$ROOT/scripts/termux-remote-commanderctl.sh"
INSTALL="$ROOT/scripts/install-direct-commander.sh"
GUARD="$ROOT/scripts/termux-remote-commander-config-guard.sh"
GUARD_TEST="$ROOT/scripts/termux-remote-commander-config-guard.test.sh"

bash -n "$CTL"
bash -n "$INSTALL"
bash -n "$GUARD"
bash -n "$GUARD_TEST"

grep -Fq '@wonderwhy-er/desktop-commander@0.2.51' "$CTL"
grep -Fq 'export LD_PRELOAD="$PREFIX/lib/libtermux-exec.so"' "$CTL"
grep -Fq 'sv up "$SERVICE_DIR"' "$CTL"
grep -Fq 'EXPECTED_VERSION="0.2.51"' "$INSTALL"
grep -Fq 'start-services.sh' "$INSTALL"
grep -Fq 'sv up "$PREFIX/var/service/desktop-commander"' "$INSTALL"
grep -Fq '10-morro-remote-commander.sh' "$INSTALL"
grep -Fq 'CONFIG_GUARD_DIR="$PREFIX/libexec/morro"' "$INSTALL"
grep -Fq '"$CONFIG_GUARD" >>"$HOME/.local/state/desktop-commander/remote.log" 2>&1' "$INSTALL"
bash "$GUARD_TEST"

echo "DIRECT_COMMANDER_RUNIT_REGRESSION=PASS"
