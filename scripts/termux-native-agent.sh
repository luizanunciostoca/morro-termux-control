#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

REPO="${MORRO_AGENT_REPO:-luizanunciostoca/morro-termux-control}"
OWNER="${MORRO_AGENT_OWNER:-luizanunciostoca}"
POLL_SECONDS="${MORRO_AGENT_POLL_SECONDS:-30}"
HEARTBEAT_SECONDS="${MORRO_AGENT_HEARTBEAT_SECONDS:-120}"
AGENT_BUILD="native-v3"
PROTOCOL_VERSION="2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/termux-job-protocol.sh
source "$SCRIPT_DIR/termux-job-protocol.sh"
STATE_DIR="${MORRO_AGENT_STATE_DIR:-$HOME/.morro-termux-agent}"
RESULT_DIR="$STATE_DIR/results"
DONE_DIR="$STATE_DIR/done"
CLAIMED_DIR="$STATE_DIR/claimed"
LOG_DIR="$STATE_DIR/logs"
STATUS_FILE="$STATE_DIR/status_issue"
PID_FILE="$STATE_DIR/agent.pid"
STOP_FILE="$STATE_DIR/stop"
DAEMON_LOCK_DIR="$STATE_DIR/daemon.lock"

mkdir -p "$RESULT_DIR" "$DONE_DIR" "$CLAIMED_DIR" "$LOG_DIR"
touch "$LOG_DIR/agent.log"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "ERROR missing command: $1"
    exit 69
  }
}

for c in gh jq bash timeout sha256sum base64; do
  require_cmd "$c"
done

if ! gh auth status >/dev/null 2>&1; then
  log "ERROR GitHub CLI is not authenticated."
  exit 77
fi

visibility="$(gh repo view "$REPO" --json visibility --jq '.visibility' 2>/dev/null || true)"
if [[ "$visibility" != "PRIVATE" ]]; then
  log "ERROR refusing to run: repository $REPO is not PRIVATE (got: $visibility)"
  exit 77
fi

repo_owner="$(gh repo view "$REPO" --json owner --jq '.owner.login' 2>/dev/null || true)"
if [[ "$repo_owner" != "$OWNER" ]]; then
  log "ERROR refusing to run: repository owner mismatch ($repo_owner != $OWNER)"
  exit 77
fi

list_status_issues() {
  gh api --paginate "/repos/$REPO/issues?state=open&per_page=100" \
    --jq '.[] | select(.pull_request == null) | select(.title=="[TERMUX-AGENT] status") | .number' |
    sort -n
}

ensure_status_issue() {
  local n duplicate status_output
  local -a issues=()

  if ! status_output="$(list_status_issues)"; then
    log "WARN heartbeat discovery failed; refusing to infer an empty heartbeat set"
    return 1
  fi
  if [[ -n "$status_output" ]]; then
    mapfile -t issues <<<"$status_output"
  fi

  if (( ${#issues[@]} == 0 )); then
    if ! n="$(
      gh issue create --repo "$REPO" \
        --title "[TERMUX-AGENT] status" \
        --body "Initializing native Termux agent..." |
      sed -n 's#.*/issues/##p'
    )"; then
      log "WARN heartbeat creation failed"
      return 1
    fi
    [[ "$n" =~ ^[0-9]+$ ]] || return 1

    issues=()
    if ! status_output="$(list_status_issues)"; then
      log "WARN heartbeat reconciliation failed after creation"
      return 1
    fi
    if [[ -n "$status_output" ]]; then
      mapfile -t issues <<<"$status_output"
    fi
  fi

  (( ${#issues[@]} >= 1 )) || return 1
  n="${issues[0]}"

  for duplicate in "${issues[@]:1}"; do
    gh issue comment "$duplicate" --repo "$REPO" \
      --body "MORRO_AGENT_HEARTBEAT_SUPERSEDED_V3 — canonical heartbeat is #$n. Duplicate closed by deterministic singleton reconciliation." \
      >/dev/null 2>&1 || true
    gh issue close "$duplicate" --repo "$REPO" >/dev/null 2>&1 || true
  done

  printf '%s\n' "$n" > "$STATUS_FILE"
  printf '%s' "$n"
}

boot_id() {
  local value
  value="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
  [[ -n "$value" ]] && printf '%s' "$value" || printf '%s' "unknown"
}

agent_instance_id() {
  # Stable for the lifetime of this daemon; changes across process or device boot.
  printf '%s' "$(boot_id)|$$" |
    sha256sum |
    awk '{print substr($1,1,24)}'
}

acquire_daemon_lock() {
  local old_pid
  if mkdir "$DAEMON_LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$DAEMON_LOCK_DIR/pid"
    return 0
  fi

  old_pid="$(cat "$DAEMON_LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
    log "ERROR agent singleton already running pid=$old_pid"
    exit 73
  fi

  rm -f "$DAEMON_LOCK_DIR/pid"
  rmdir "$DAEMON_LOCK_DIR" 2>/dev/null || {
    log "ERROR unable to recover stale daemon lock"
    exit 73
  }
  if ! mkdir "$DAEMON_LOCK_DIR" 2>/dev/null; then
    log "ERROR daemon lock was concurrently acquired"
    exit 73
  fi
  printf '%s\n' "$$" > "$DAEMON_LOCK_DIR/pid"
}

release_daemon_lock() {
  local lock_pid
  lock_pid="$(cat "$DAEMON_LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ "$lock_pid" == "$$" ]]; then
    rm -f "$DAEMON_LOCK_DIR/pid"
    rmdir "$DAEMON_LOCK_DIR" 2>/dev/null || true
  fi
}

heartbeat() {
  local status_issue now host arch body boot instance
  status_issue="$(ensure_status_issue)" || {
    log "WARN unable to resolve status issue"
    return 0
  }

  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  host="$(hostname 2>/dev/null || echo android)"
  arch="$(uname -m)"
  boot="$(boot_id)"
  instance="$(agent_instance_id)"
  body="$(cat <<EOF
MORRO_NATIVE_AGENT_V3

state: ONLINE
build: $AGENT_BUILD
protocol_version: $PROTOCOL_VERSION
agent_instance_id: $instance
boot_id: $boot
heartbeat_utc: $now
host: $host
arch: $arch
pid: $$
poll_seconds: $POLL_SECONDS
repo: $REPO
transport: GitHub Issues
targets: termux,debian
EOF
)"

  gh issue edit "$status_issue" --repo "$REPO" --body "$body" >/dev/null 2>&1 ||     log "WARN heartbeat update failed"
}

validate_request() {
  morro_validate_request_file /dev/stdin
}

has_matching_preflight() {
  local issue="$1" request_hash="$2" rows row body
  if ! rows="$(gh api --paginate "/repos/$REPO/issues/$issue/comments?per_page=100" \
    --jq '.[] | select(.user.login=="github-actions[bot]") | .body | @base64')"; then
    return 1
  fi
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    body="$(printf '%s' "$row" | base64 -d)"
    if morro_preflight_body_matches "$body" "$request_hash"; then
      return 0
    fi
  done <<<"$rows"
  return 1
}

resolve_termux_cwd() {
  local cwd="$1"
  if [[ "$cwd" == "~" ]]; then
    printf '%s' "$HOME"
  elif [[ "$cwd" == "~/"* ]]; then
    printf '%s/%s' "$HOME" "${cwd:2}"
  else
    printf '%s' "$cwd"
  fi
}

publish_result() {
  local issue="$1" result_meta="$2" stdout_log="$3" stderr_log="$4"
  local id target exit_code started ended duration hash out err comment_file

  id="$(jq -er '.id' "$result_meta")"
  target="$(jq -er '.target' "$result_meta")"
  exit_code="$(jq -er '.exit_code' "$result_meta")"
  started="$(jq -er '.started_at' "$result_meta")"
  ended="$(jq -er '.ended_at' "$result_meta")"
  duration="$(jq -er '.duration_seconds' "$result_meta")"
  hash="$(jq -er '.request_sha256' "$result_meta")"

  out="$(tail -c 12000 "$stdout_log" 2>/dev/null || true)"
  err="$(tail -c 12000 "$stderr_log" 2>/dev/null || true)"
  comment_file="$RESULT_DIR/$issue/comment.md"

  {
    echo "MORRO_AGENT_RESULT_V3"
    echo
    printf '%s\n' "- id: $id"
    printf '%s\n' "- target: $target"
    printf '%s\n' "- exit_code: $exit_code"
    printf '%s\n' "- started_at: $started"
    printf '%s\n' "- ended_at: $ended"
    printf '%s\n' "- duration_seconds: $duration"
    printf '%s\n' "- request_sha256: $hash"
    echo
    echo "#### metadata_json"
    echo '\`\`\`json'
    jq -c . "$result_meta"
    echo '\`\`\`'
    echo
    echo "#### stdout (last 12000 bytes)"
    echo '\`\`\`text'
    printf '%s\n' "$out"
    echo '\`\`\`'
    echo
    echo "#### stderr (last 12000 bytes)"
    echo '\`\`\`text'
    printf '%s\n' "$err"
    echo '\`\`\`'
    echo
    echo "Full local logs remain on the tablet under:"
    printf '%s\n' "$RESULT_DIR/$issue/"
  } > "$comment_file"

  if gh issue comment "$issue" --repo "$REPO" --body-file "$comment_file" >/dev/null; then
    gh issue close "$issue" --repo "$REPO" >/dev/null
    log "Published and closed issue #$issue (exit=$exit_code)"
    return 0
  fi

  log "WARN result publish failed for issue #$issue; execution will NOT repeat"
  return 1
}

execute_issue() {
  local issue="$1" title="$2" body="$3" author="$4"
  local req_file result_path stdout_log stderr_log script_file
  local id target cwd timeout_s command_text request_hash started ended
  local start_epoch end_epoch duration rc termux_cwd cmd_b64

  [[ "$author" == "$OWNER" ]] || {
    log "SKIP issue #$issue: unauthorized author=$author"
    return 0
  }

  [[ "$title" == "[TERMUX-JOB] "* ]] || return 0

  req_file="$RESULT_DIR/$issue/request.json"
  result_path="$RESULT_DIR/$issue/result.json"
  stdout_log="$RESULT_DIR/$issue/stdout.log"
  stderr_log="$RESULT_DIR/$issue/stderr.log"
  script_file="$RESULT_DIR/$issue/command.sh"
  mkdir -p "$RESULT_DIR/$issue"

  if ! body="$(gh api "/repos/$REPO/issues/$issue" --jq '.body // ""')"; then
    log "WAIT issue #$issue: unable to refetch current body"
    return 0
  fi
  printf '%s' "$body" > "$req_file"

  if ! validate_request < "$req_file"; then
    log "REJECT issue #$issue: invalid v2 request schema"
    gh issue comment "$issue" --repo "$REPO"       --body "MORRO_AGENT_REJECTED_V2: invalid request schema or missing confirm=EXECUTE." >/dev/null || true
    gh issue close "$issue" --repo "$REPO" >/dev/null || true
    return 0
  fi

  id="$(jq -r '.id' "$req_file")"
  target="$(jq -r '.target' "$req_file")"
  cwd="$(jq -r '.cwd // "~"' "$req_file")"
  timeout_s="$(jq -r '.timeout_seconds // 900 | floor' "$req_file")"
  command_text="$(jq -r '.command' "$req_file")"
  request_hash="$(morro_request_sha256 "$req_file")"

  if ! has_matching_preflight "$issue" "$request_hash"; then
    log "WAIT issue #$issue: no matching github-actions preflight for request_sha256=$request_hash"
    return 0
  fi

  if [[ -f "$DONE_DIR/$issue.json" ]]; then
    if [[ -f "$result_path" ]]; then
      publish_result "$issue" "$result_path" "$stdout_log" "$stderr_log" || true
    fi
    return 0
  fi

  if [[ -f "$CLAIMED_DIR/$issue.json" ]]; then
    log "RECOVERY issue #$issue was previously claimed without a completed result; refusing automatic re-execution"
    if [[ ! -f "$CLAIMED_DIR/$issue.recovery-reported" ]]; then
      gh issue comment "$issue" --repo "$REPO"         --body "MORRO_AGENT_RECOVERY_REQUIRED_V2 — this job was previously claimed on the tablet, but no completed result was recorded. Automatic re-execution is blocked to prevent duplicate side effects." >/dev/null || true
      touch "$CLAIMED_DIR/$issue.recovery-reported"
    fi
    return 0
  fi

  jq -n     --arg issue "$issue"     --arg id "$id"     --arg request_sha256 "$request_hash"     --arg claimed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"     '{issue: $issue, id: $id, request_sha256: $request_sha256, claimed_at: $claimed_at}'     > "$CLAIMED_DIR/$issue.json"

  gh issue comment "$issue" --repo "$REPO"     --body "MORRO_AGENT_CLAIM_V2 — agent accepted issue #$issue at $(date -u +%Y-%m-%dT%H:%M:%SZ)." >/dev/null || {
      rm -f "$CLAIMED_DIR/$issue.json"
      log "WARN unable to claim issue #$issue; skipping this cycle"
      return 0
    }

  live_req="$RESULT_DIR/$issue/request-live.json"
  if ! gh api "/repos/$REPO/issues/$issue" --jq '.body // ""' > "$live_req" ||
     ! morro_validate_request_file "$live_req" ||
     [[ "$(morro_request_sha256 "$live_req")" != "$request_hash" ]]; then
    rm -f "$CLAIMED_DIR/$issue.json" "$live_req"
    log "WAIT issue #$issue: body changed after preflight/claim; refusing execution"
    return 0
  fi
  rm -f "$live_req"

  {
    echo '#!/data/data/com.termux/files/usr/bin/bash'
    echo 'set -Eeuo pipefail'
    printf '%s\n' "$command_text"
  } > "$script_file"
  chmod 700 "$script_file"

  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  start_epoch="$(date +%s)"
  rc=0

  log "EXEC issue #$issue id=$id target=$target timeout=$timeout_s"

  set +e
  if [[ "$target" == "termux" ]]; then
    termux_cwd="$(resolve_termux_cwd "$cwd")"
    if [[ ! -d "$termux_cwd" ]]; then
      printf 'Working directory does not exist: %s\n' "$termux_cwd" > "$stderr_log"
      : > "$stdout_log"
      rc=66
    else
      (
        cd "$termux_cwd"
        timeout --signal=TERM --kill-after=10s "${timeout_s}s" bash "$script_file"
      ) > "$stdout_log" 2> "$stderr_log"
      rc=$?
    fi
  else
    if ! command -v proot-distro >/dev/null 2>&1; then
      : > "$stdout_log"
      echo "proot-distro is not installed" > "$stderr_log"
      rc=69
    else
      cmd_b64="$(printf '%s' "$command_text" | base64 | tr -d '\n')"
      timeout --signal=TERM --kill-after=10s "${timeout_s}s"         proot-distro login debian --         env MORRO_CMD_B64="$cmd_b64" MORRO_CWD="$cwd"         bash -lc '
          set -Eeuo pipefail
          c="$MORRO_CWD"
          if [[ "$c" == "~" ]]; then c="$HOME"; elif [[ "$c" == "~/"* ]]; then c="$HOME/${c:2}"; fi
          cd "$c"
          printf "%s" "$MORRO_CMD_B64" | base64 -d | bash
        ' > "$stdout_log" 2> "$stderr_log"
      rc=$?
    fi
  fi
  set -e

  ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  end_epoch="$(date +%s)"
  duration="$((end_epoch - start_epoch))"

  jq -n     --arg id "$id"     --arg target "$target"     --arg started_at "$started"     --arg ended_at "$ended"     --arg request_sha256 "$request_hash"     --argjson duration_seconds "$duration"     --argjson exit_code "$rc"     '{
      id: $id,
      target: $target,
      started_at: $started_at,
      ended_at: $ended_at,
      duration_seconds: $duration_seconds,
      exit_code: $exit_code,
      request_sha256: $request_sha256
    }' > "$result_path"

  cp "$result_path" "$DONE_DIR/$issue.json"
  rm -f "$CLAIMED_DIR/$issue.json" "$CLAIMED_DIR/$issue.recovery-reported"
  publish_result "$issue" "$result_path" "$stdout_log" "$stderr_log" || true
}

run_once() {
  local rows row obj issue title body author

  if ! rows="$(
    gh api --paginate "/repos/$REPO/issues?state=open&per_page=100" \
      --jq '.[] |
        select(.pull_request == null) |
        select(.title | startswith("[TERMUX-JOB] ")) |
        {number: .number, title: .title, body: (.body // ""), author: {login: (.user.login // "")}} |
        @base64'
  )"; then
    log "WARN unable to enumerate open Termux jobs"
    return 1
  fi

  [[ -n "$rows" ]] || return 0

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    obj="$(printf '%s' "$row" | base64 -d)"
    issue="$(jq -r '.number' <<<"$obj")"
    title="$(jq -r '.title' <<<"$obj")"
    body="$(jq -r '.body' <<<"$obj")"
    author="$(jq -r '.author.login // ""' <<<"$obj")"
    execute_issue "$issue" "$title" "$body" "$author"
  done <<< "$rows"
}

mode="${1:-daemon}"

case "$mode" in
  once)
    heartbeat
    run_once
    ;;
  daemon)
    acquire_daemon_lock
    rm -f "$STOP_FILE"
    printf '%s\n' "$$" > "$PID_FILE"
    cleanup_agent() {
      local recorded_pid
      recorded_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
      if [[ "$recorded_pid" == "$$" ]]; then
        rm -f "$PID_FILE"
      fi
      release_daemon_lock
      log "Agent stopped"
    }
    trap 'exit 0' INT TERM
    trap 'cleanup_agent' EXIT
    termux-wake-lock >/dev/null 2>&1 || true
    log "MORRO_NATIVE_AGENT_V3 started build=$AGENT_BUILD repo=$REPO poll=${POLL_SECONDS}s"
    last_heartbeat=0
    while [[ ! -f "$STOP_FILE" ]]; do
      now_epoch="$(date +%s)"
      if (( now_epoch - last_heartbeat >= HEARTBEAT_SECONDS )); then
        heartbeat
        last_heartbeat="$now_epoch"
      fi
      run_once || log "WARN polling cycle returned non-zero"
      sleep "$POLL_SECONDS"
    done
    ;;
  *)
    echo "usage: $0 {daemon|once}" >&2
    exit 64
    ;;
esac
