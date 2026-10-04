#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
CONFIG_FILE="${MORRO_COMMANDER_CONFIG_FILE:-$HOME/.claude-server-commander/config.json}"
NODE_BIN="${MORRO_COMMANDER_NODE_BIN:-$PREFIX/bin/node}"

if [[ ! -e "$CONFIG_FILE" ]]; then
  echo "commander_config=ABSENT action=REGENERATE"
  exit 0
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "commander_config=BLOCKED reason=CONFIG_NOT_REGULAR path=$CONFIG_FILE" >&2
  exit 78
fi

if "$NODE_BIN" -e '
  const fs = require("fs");
  const path = process.argv[1];
  const raw = fs.readFileSync(path, "utf8");
  const parsed = JSON.parse(raw);
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) process.exit(2);
' "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "commander_config=VALID"
  exit 0
fi

ts="$(date -u +%Y%m%dT%H%M%SZ)"
backup="$CONFIG_FILE.corrupt-$ts-$$"
mv "$CONFIG_FILE" "$backup"
echo "commander_config=QUARANTINED backup=$backup action=REGENERATE"
