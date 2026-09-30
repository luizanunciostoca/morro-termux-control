#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

REPO="${MORRO_AGENT_REPO:-luizanunciostoca/morro-termux-control}"
OWNER="${MORRO_AGENT_OWNER:-luizanunciostoca}"
POLL_SECONDS="${MORRO_AGENT_POLL_SECONDS:-30}"
STATE_DIR="${MORRO_AGENT_STATE_DIR:-$HOME/.morro-termux-agent}"
RESULT_DIR="$STATE_DIR/results"
DONE_DIR="$STATE_DIR/done"
LOG_DIR="$STATE_DIR/logs"
STATUS_FILE="$STATE_DIR/status_issue"
PID_FILE="$STATE_DIR/agent.pid"
STOP_FILE="$STATE_DIR/stop"

mkdir -p "$RESULT_DIR" "$DONE_DIR" "$LOG_DIR"
touch "$LOG_DIR/agent.log"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG_DIR/agent.log"
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

ensure_status_issue() {
  local n
  if [[ -f "$STATUS_FILE" ]]; then
    n="$(cat "$STATUS_FILE" 2>/dev/null || true)"
    if [[ "$n" =~ ^[0-9]+$ ]] && gh issue view "$n" --repo "$REPO" >/dev/null 2>&1; then
      printf '%s' "$n"
      return 0
    fi
  fi

  n="$(
    gh issue list --repo "$REPO" --state open --limit 100       --json number,title       --jq '.[] | select(.title=="[TERMUX-AGENT] status") | .number' |
      head -n 1
  )"

  if [[ -z "$n" ]]; then
    n="$(
      gh issue create --repo "$REPO"         --title "[TERMUX-AGENT] status"         --body "Initializing native Termux agent..." |
      sed -n 's#.*/issues/##p'
    )"
  fi

  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$n" > "$STATUS_FILE"
  printf '%s' "$n"
}

heartbeat() {
  local status_issue now host arch body
  status_issue="$(ensure_status_issue)" || {
    log "WARN unable to resolve status issue"
    return 0
  }

  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  host="$(hostname 2>/dev/null || echo android)"
  arch="$(uname -m)"
  body="$(cat <<EOF
MORRO_NATIVE_AGENT_V2

state: ONLINE
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
  jq -e '
    type == "object" and
    .version == 2 and
    .confirm == "EXECUTE" and
    (.id | type == "string" and test("^[A-Za-z0-9._-]{1,128}$")) and
    (.target == "termux" or .target == "debian") and
    (.command | type == "string" and length > 0) and
    ((.cwd // "~") | type == "string" and length > 0) and
    ((.timeout_seconds // 900) | type == "number" and . >= 1 and . <= 3600)
  ' >/dev/null
}

resolve_termux_cwd() {
  local cwd="$1"
  if [[ "$cwd" == "~" ]]; then
    printf '%s' "$HOME"
  elif [[ "$cwd" == "~/"* ]]; then
    printf '%s/%s' "$HOME" "${cwd#~/}"
  else
    printf '%s' "$cwd"
  fi
}

publish_result() {
  local issue="$1" result_meta="$2" stdout_log="$3" stderr_log="$4"
  local id target exit_code started ended duration hash out err body

  id="$(jq -r '.id' "$result_meta")"
  target="$(jq -r '.target' "$result_meta")"
  exit_code="$(jq -r '.exit_code' "$result_meta")"
  started="$(jq -r '.started_at' "$result_meta")"
  ended="$(jq -r '.ended_at' "$result_meta")"
  duration="$(jq -r '.duration_seconds' "$result_meta")"
  hash="$(jq -r '.request_sha256' "$result_meta")"

  out="$(tail -c 12000 "$stdout_log" 2>/dev/null || true)"
  err="$(tail -c 12000 "$stderr_log" 2>/dev/null || true)"

  body="$(cat <<EOF
MORRO_AGENT_RESULT_V2

- id: `$id`
- target: `$target`
- exit_code: `$exit_code`
- started_at: `$started`
- ended_at: `$ended`
- duration_seconds: `$duration`
- request_sha256: `$hash`

#### stdout (last 12000 bytes)
\`\`\`text
$out
\`\`\`

#### stderr (last 12000 bytes)
\`\`\`text
$err
\`\`\`

Full local logs remain on the tablet under:
`$RESULT_DIR/$issue/`
EOF
)"

  if gh issue comment "$issue" --repo "$REPO" --body "$body" >/dev/null; then
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

  printf '%s' "$body" > "$req_file"

  if ! validate_request < "$req_file"; then
    log "REJECT issue #$issue: invalid v2 request schema"
    gh issue comment "$issue" --repo "$REPO"       --body "MORRO_AGENT_REJECTED_V2: invalid request schema or missing `confirm: EXECUTE`." >/dev/null || true
    gh issue close "$issue" --repo "$REPO" >/dev/null || true
    return 0
  fi

  id="$(jq -r '.id' "$req_file")"
  target="$(jq -r '.target' "$req_file")"
  cwd="$(jq -r '.cwd // "~"' "$req_file")"
  timeout_s="$(jq -r '.timeout_seconds // 900 | floor' "$req_file")"
  command_text="$(jq -r '.command' "$req_file")"
  request_hash="$(sha256sum "$req_file" | awk '{print $1}')"

  if [[ -f "$DONE_DIR/$issue.json" ]]; then
    if [[ -f "$result_path" ]]; then
      publish_result "$issue" "$result_path" "$stdout_log" "$stderr_log" || true
    fi
    return 0
  fi

  gh issue comment "$issue" --repo "$REPO"     --body "MORRO_AGENT_CLAIM_V2 — agent accepted issue #$issue at $(date -u +%Y-%m-%dT%H:%M:%SZ)." >/dev/null || {
      log "WARN unable to claim issue #$issue; skipping this cycle"
      return 0
    }

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
          if [[ "$c" == "~" ]]; then c="$HOME"; elif [[ "$c" == "~/"* ]]; then c="$HOME/${c#~/}"; fi
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
  publish_result "$issue" "$result_path" "$stdout_log" "$stderr_log" || true
}

run_once() {
  local rows
  rows="$(
    gh issue list --repo "$REPO" --state open --limit 100       --json number,title,body,author       --jq '.[] | select(.title | startswith("[TERMUX-JOB] ")) | @base64'
  )"

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
    rm -f "$STOP_FILE"
    printf '%s\n' "$$" > "$PID_FILE"
    trap 'rm -f "$PID_FILE"; log "Agent stopped"; exit 0' INT TERM EXIT
    termux-wake-lock >/dev/null 2>&1 || true
    log "MORRO_NATIVE_AGENT_V2 started repo=$REPO poll=${POLL_SECONDS}s"
    last_heartbeat=0
    while [[ ! -f "$STOP_FILE" ]]; do
      now_epoch="$(date +%s)"
      if (( now_epoch - last_heartbeat >= 120 )); then
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
