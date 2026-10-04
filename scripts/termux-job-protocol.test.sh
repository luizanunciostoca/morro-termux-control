#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/termux-job-protocol.sh
source "$ROOT/scripts/termux-job-protocol.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/request-a.json" <<'JSON'
{
  "version": 2,
  "confirm": "EXECUTE",
  "id": "nested-quotes",
  "target": "termux",
  "cwd": "~",
  "timeout_seconds": 120,
  "command": "printf '%s\\n' \"a \\\"quoted\\\" value\"; printf 'line1\\nline2\\n'"
}
JSON

cat >"$tmp/request-b.json" <<'JSON'
{"command":"printf '%s\\n' \"a \\\"quoted\\\" value\"; printf 'line1\\nline2\\n'","cwd":"~","confirm":"EXECUTE","timeout_seconds":120,"target":"termux","id":"nested-quotes","version":2}
JSON

morro_validate_request_file "$tmp/request-a.json"
morro_validate_request_file "$tmp/request-b.json"

hash_a="$(morro_request_sha256 "$tmp/request-a.json")"
hash_b="$(morro_request_sha256 "$tmp/request-b.json")"
[[ "$hash_a" == "$hash_b" ]]

marker="$(morro_preflight_marker "$hash_a")"
morro_preflight_body_matches "$marker" "$hash_a"
! morro_preflight_body_matches "$marker" "$(printf x | sha256sum | awk '{print $1}')"

jq '.command += "; echo edited"' "$tmp/request-a.json" >"$tmp/edited.json"
hash_edited="$(morro_request_sha256 "$tmp/edited.json")"
[[ "$hash_edited" != "$hash_a" ]]
! morro_preflight_body_matches "$marker" "$hash_edited"

printf '{"version":2,"confirm":"EXECUTE","command":"unterminated}' >"$tmp/invalid.json"
if morro_validate_request_file "$tmp/invalid.json" >/dev/null 2>&1; then
  echo "invalid JSON unexpectedly accepted" >&2
  exit 1
fi

printf '%s\n' "MORRO_TERMUX_JOB_PROTOCOL_REGRESSION_PASS hash=$hash_a"
