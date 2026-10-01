#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT="$ROOT/scripts/termux-native-agent.sh"
CTL="$ROOT/scripts/termux-native-agentctl.sh"
SUP="$ROOT/scripts/termux-native-supervisor.sh"
DOC="$ROOT/CHATGPT-START-HERE.md"

for script in "$AGENT" "$CTL" "$SUP"; do
  bash -n "$script"
done

grep -Fq 'gh api --paginate "/repos/$REPO/issues?state=open&per_page=100"' "$AGENT"
grep -Fq 'select(.title=="[TERMUX-AGENT] status")' "$AGENT"
grep -Fq 'select(.title | startswith("[TERMUX-JOB] "))' "$AGENT"
grep -Fq 'refusing to infer an empty heartbeat set' "$AGENT"
grep -Fq 'printf '\''%s\n'\'' "$$" > "$DAEMON_LOCK_DIR/pid"' "$AGENT"
grep -Fq 'printf '\''%s\n'\'' "$$" > "$PID_FILE"' "$AGENT"
grep -Fq 'pid: $$' "$AGENT"
grep -Fq "trap 'exit 0' INT TERM" "$AGENT"
grep -Fq "trap 'cleanup_agent' EXIT" "$AGENT"
grep -Fq 'recover)' "$CTL"
grep -Fq "trap 'exit 0' INT TERM" "$SUP"

if grep -Fq 'current canonical issue: **#' "$DOC"; then
  echo "documentation regressed to a hardcoded heartbeat issue number" >&2
  exit 1
fi

if grep -Fq 'gh issue list --repo "$REPO" --state open --limit 100' "$AGENT"; then
  echo "agent discovery regressed to bounded issue listing" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/state"

cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

case "${1:-}" in
  auth)
    exit 0
    ;;
  repo)
    if [[ "${2:-}" == "view" && "$*" == *"visibility"* ]]; then
      printf 'PRIVATE\n'
    elif [[ "${2:-}" == "view" && "$*" == *"owner"* ]]; then
      printf 'luizanunciostoca\n'
    fi
    exit 0
    ;;
  api)
    if [[ "$*" == *'select(.title=="[TERMUX-AGENT] status")'* ]]; then
      printf '4\n'
    fi
    exit 0
    ;;
  issue)
    exit 0
    ;;
esac
exit 0
EOF

cat >"$TMP/bin/termux-wake-lock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$TMP/bin/termux-wake-unlock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/bin/"*

export PATH="$TMP/bin:$PATH"
export MORRO_AGENT_STATE_DIR="$TMP/state"
export MORRO_AGENT_POLL_SECONDS=1
export MORRO_AGENT_HEARTBEAT_SECONDS=1

bash "$AGENT" daemon >"$TMP/daemon-1.log" 2>&1 &
PID1=$!

for _ in $(seq 1 40); do
  [[ -s "$TMP/state/agent.pid" && -s "$TMP/state/daemon.lock/pid" ]] && break
  sleep 0.1
done

RECORDED="$(cat "$TMP/state/agent.pid")"
LOCKED="$(cat "$TMP/state/daemon.lock/pid")"
test "$RECORDED" = "$PID1"
test "$LOCKED" = "$PID1"

set +e
bash "$AGENT" daemon >"$TMP/daemon-2.log" 2>&1
RC2=$?
set -e
test "$RC2" = 73
test "$(cat "$TMP/state/daemon.lock/pid")" = "$PID1"

kill -TERM "$PID1"
for _ in $(seq 1 40); do
  kill -0 "$PID1" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$PID1" 2>/dev/null; then
  echo "daemon did not exit on TERM" >&2
  exit 1
fi

test ! -e "$TMP/state/agent.pid"
test ! -e "$TMP/state/daemon.lock/pid"
test ! -d "$TMP/state/daemon.lock"

echo "TERMUX_NATIVE_AGENT_LIFECYCLE_REGRESSION=PASS"
