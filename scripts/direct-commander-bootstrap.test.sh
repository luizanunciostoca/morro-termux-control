#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="$ROOT/scripts/termux-remote-commanderctl.sh"
SUP="$ROOT/scripts/termux-remote-commander-supervisor.sh"
INSTALL="$ROOT/scripts/install-direct-commander.sh"

for f in "$CTL" "$SUP" "$INSTALL"; do
  bash -n "$f"
done

grep -Fq '@wonderwhy-er/desktop-commander@0.2.52' "$CTL"
grep -Fq 'exec npx -y "$PACKAGE" remote' "$CTL"
grep -Fq 'commander=PAIR_REQUIRED' "$CTL"
grep -Fq 'direct_access=PAIR_REQUIRED' "$INSTALL"
grep -Fq "trap 'exit 0' INT TERM" "$SUP"
grep -Fq '10-morro-remote-commander.sh' "$INSTALL"
grep -Fq '00-morro-remote.sh.disabled' "$INSTALL"

echo "DIRECT_COMMANDER_BOOTSTRAP_REGRESSION=PASS"
