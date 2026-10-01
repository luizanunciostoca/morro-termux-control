#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="$ROOT/scripts/termux-remote-commanderctl.sh"
INSTALL="$ROOT/scripts/install-direct-commander.sh"

bash -n "$CTL"
bash -n "$INSTALL"

grep -Fq '@wonderwhy-er/desktop-commander@0.2.51' "$CTL"
grep -Fq 'export LD_PRELOAD="$PREFIX/lib/libtermux-exec.so"' "$CTL"
grep -Fq 'sv up "$SERVICE_DIR"' "$CTL"
grep -Fq 'EXPECTED_VERSION="0.2.51"' "$INSTALL"
grep -Fq 'start-services.sh' "$INSTALL"
grep -Fq 'sv up "$PREFIX/var/service/desktop-commander"' "$INSTALL"
grep -Fq '10-morro-remote-commander.sh' "$INSTALL"

echo "DIRECT_COMMANDER_RUNIT_REGRESSION=PASS"
