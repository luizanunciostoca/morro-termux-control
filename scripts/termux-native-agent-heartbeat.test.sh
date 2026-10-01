#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT="$ROOT/scripts/termux-native-agent.sh"
DOC="$ROOT/CHATGPT-START-HERE.md"

bash -n "$AGENT"

grep -Fq 'gh api --paginate "/repos/$REPO/issues?state=open&per_page=100"' "$AGENT"
grep -Fq 'select(.title=="[TERMUX-AGENT] status")' "$AGENT"
grep -Fq 'sort -n' "$AGENT"
grep -Fq 'MORRO_AGENT_HEARTBEAT_SUPERSEDED_V3' "$AGENT"
grep -Fq 'protocol_version: $PROTOCOL_VERSION' "$AGENT"
grep -Fq 'agent_instance_id: $instance' "$AGENT"
grep -Fq 'boot_id: $boot' "$AGENT"
grep -Fq 'acquire_daemon_lock' "$AGENT"

if grep -F 'gh issue list --repo "$REPO" --state open --limit 100' "$AGENT" |
  grep -Fq '[TERMUX-AGENT] status'; then
  echo "heartbeat discovery regressed to bounded issue listing" >&2
  exit 1
fi

if grep -Fq 'current canonical issue: **#' "$DOC"; then
  echo "documentation regressed to a hardcoded heartbeat issue number" >&2
  exit 1
fi

echo "TERMUX_HEARTBEAT_SINGLETON_REGRESSION=PASS"
