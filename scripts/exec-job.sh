#!/usr/bin/env bash
set -Eeuo pipefail

request="${1:-}"
[[ -n "$request" && -f "$request" ]] || {
  echo "usage: $0 jobs/requests/<job>.json" >&2
  exit 64
}

command -v jq >/dev/null || {
  echo "jq is required" >&2
  exit 69
}
command -v timeout >/dev/null || {
  echo "GNU timeout is required" >&2
  exit 69
}

jq -e '
  type == "object" and
  .version == 1 and
  (.id | type == "string" and length > 0) and
  (.command | type == "string" and length > 0) and
  ((.cwd // "~") | type == "string") and
  ((.timeout_seconds // 900) | type == "number")
' "$request" >/dev/null || {
  echo "Invalid request schema: $request" >&2
  exit 65
}

id="$(jq -r '.id' "$request")"
command_text="$(jq -r '.command' "$request")"
cwd="$(jq -r '.cwd // "~"' "$request")"
timeout_seconds="$(jq -r '.timeout_seconds // 900 | floor' "$request")"
description="$(jq -r '.description // ""' "$request")"

[[ "$id" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || {
  echo "Invalid job id" >&2
  exit 65
}

if (( timeout_seconds < 1 || timeout_seconds > 3600 )); then
  echo "timeout_seconds must be between 1 and 3600" >&2
  exit 65
fi

if [[ "$cwd" == "~" ]]; then
  cwd="$HOME"
elif [[ "$cwd" == "~/"* ]]; then
  cwd="$HOME/${cwd#~/}"
fi

[[ -d "$cwd" ]] || {
  echo "Working directory does not exist: $cwd" >&2
  exit 66
}

workspace="${GITHUB_WORKSPACE:-$PWD}"
results_root="$workspace/.morro-control/results"
result_dir="$results_root/$id"
mkdir -p "$result_dir"

stdout_log="$result_dir/stdout.log"
stderr_log="$result_dir/stderr.log"
metadata="$result_dir/result.json"
script_file="$result_dir/command.sh"

{
  echo '#!/usr/bin/env bash'
  echo 'set -Eeuo pipefail'
  printf '%s\n' "$command_text"
} > "$script_file"
chmod 700 "$script_file"

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
started_epoch="$(date +%s)"

echo "=== MORRO TERMUX JOB ==="
echo "id: $id"
echo "description: $description"
echo "cwd: $cwd"
echo "timeout_seconds: $timeout_seconds"
echo "started_at: $started_at"

set +e
(
  cd "$cwd"
  timeout --signal=TERM --kill-after=10s "${timeout_seconds}s" /bin/bash "$script_file"
) > >(tee "$stdout_log") 2> >(tee "$stderr_log" >&2)
rc=$?
set -e

ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ended_epoch="$(date +%s)"
duration="$((ended_epoch - started_epoch))"

jq -n   --arg id "$id"   --arg description "$description"   --arg cwd "$cwd"   --arg started_at "$started_at"   --arg ended_at "$ended_at"   --argjson duration_seconds "$duration"   --argjson exit_code "$rc"   '{
    id: $id,
    description: $description,
    cwd: $cwd,
    started_at: $started_at,
    ended_at: $ended_at,
    duration_seconds: $duration_seconds,
    exit_code: $exit_code
  }' > "$metadata"

echo "ended_at: $ended_at"
echo "duration_seconds: $duration"
echo "exit_code: $rc"
echo "result_dir: $result_dir"

exit "$rc"
