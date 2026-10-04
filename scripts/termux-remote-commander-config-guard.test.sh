#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/scripts/termux-remote-commander-config-guard.sh"
NODE_BIN="$(command -v node)"
D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
CFG="$D/config.json"

printf '%s\n' '{"allowedDirectories":[],"telemetryEnabled":false}' >"$CFG"
before="$(sha256sum "$CFG" | awk '{print $1}')"
out="$(MORRO_COMMANDER_CONFIG_FILE="$CFG" MORRO_COMMANDER_NODE_BIN="$NODE_BIN" bash "$GUARD")"
grep -Fq 'commander_config=VALID' <<<"$out"
after="$(sha256sum "$CFG" | awk '{print $1}')"
test "$before" = "$after"

"$NODE_BIN" -e 'require("fs").writeFileSync(process.argv[1], Buffer.alloc(1858))' "$CFG"
out="$(MORRO_COMMANDER_CONFIG_FILE="$CFG" MORRO_COMMANDER_NODE_BIN="$NODE_BIN" bash "$GUARD")"
grep -Fq 'commander_config=QUARANTINED' <<<"$out"
test ! -e "$CFG"
mapfile -t backups < <(find "$D" -maxdepth 1 -type f -name 'config.json.corrupt-*' -print)
test "${#backups[@]}" -eq 1
"$NODE_BIN" -e 'const b=require("fs").readFileSync(process.argv[1]); if (b.length!==1858 || b.some(x=>x!==0)) process.exit(1)' "${backups[0]}"

rm -f "$CFG"
out="$(MORRO_COMMANDER_CONFIG_FILE="$CFG" MORRO_COMMANDER_NODE_BIN="$NODE_BIN" bash "$GUARD")"
grep -Fq 'commander_config=ABSENT action=REGENERATE' <<<"$out"

echo "DIRECT_COMMANDER_CONFIG_GUARD_REGRESSION=PASS"
