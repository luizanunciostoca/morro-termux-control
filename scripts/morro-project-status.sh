#!/usr/bin/env bash
set -euo pipefail

FULL=false
for arg in "$@"; do
  case "$arg" in
    --json) ;;
    --full) FULL=true ;;
    *) echo "MORRO_STATUS_ARGUMENT_INVALID:$arg" >&2; exit 64 ;;
  esac
done

command -v gh >/dev/null || { echo "MORRO_STATUS_GH_REQUIRED" >&2; exit 69; }
command -v jq >/dev/null || { echo "MORRO_STATUS_JQ_REQUIRED" >&2; exit 69; }

ROOT_HOME="${MORRO_STATUS_HOME:-$HOME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_REPO="luizanunciostoca/morro-termux-control"
repo_specs=(
  "platform|luizanunciostoca/touristic-digital-platform|$ROOT_HOME/touristic-digital-platform|$ROOT_HOME/repos/touristic-digital-platform.git"
  "lab|luizanunciostoca/morro-integration-lab|$ROOT_HOME/morro-integration-lab|$ROOT_HOME/repos/morro-integration-lab.git"
  "control|luizanunciostoca/morro-termux-control|$ROOT_HOME/morro-termux-control|$ROOT_HOME/repos/morro-termux-control.git"
)

repositories='[]'
for spec in "${repo_specs[@]}"; do
  IFS='|' read -r name repository checkout bare <<<"$spec"
  live_main="$(gh api "repos/$repository/commits/main" --jq .sha)"
  [[ "$live_main" =~ ^[0-9a-f]{40}$ ]] || exit 65
  prs="$(gh pr list -R "$repository" --state open --limit 100 \
    --json number,title,headRefName,headRefOid,baseRefName,isDraft,updatedAt)"
  jq -e 'type=="array"' >/dev/null <<<"$prs"

  branch_count=null
  if [[ "$FULL" == true ]]; then
    branch_count="$(gh api --paginate "repos/$repository/branches?per_page=100" \
      --jq '.[].name' | wc -l | tr -d ' ')"
  fi

  checkout_exists=false local_head="" local_branch="" local_origin="" local_dirty=null
  if [[ -d "$checkout/.git" ]]; then
    checkout_exists=true
    local_head="$(git -C "$checkout" rev-parse HEAD 2>/dev/null || true)"
    local_branch="$(git -C "$checkout" branch --show-current 2>/dev/null || true)"
    local_origin="$(git -C "$checkout" rev-parse origin/main 2>/dev/null || true)"
    [[ -z "$(git -C "$checkout" status --porcelain --untracked-files=all 2>/dev/null || true)" ]] \
      && local_dirty=false || local_dirty=true
  fi

  bare_exists=false bare_main=""
  if [[ -d "$bare" ]] &&
    [[ "$(git --git-dir="$bare" rev-parse --is-bare-repository 2>/dev/null || true)" == true ]]; then
    bare_exists=true
    bare_main="$(git --git-dir="$bare" rev-parse main 2>/dev/null || true)"
  fi

  entry="$(jq -n \
    --arg name "$name" --arg repository "$repository" --arg liveMain "$live_main" \
    --arg checkoutPath "$checkout" --arg localHead "$local_head" \
    --arg localBranch "$local_branch" --arg localOrigin "$local_origin" \
    --arg barePath "$bare" --arg bareMain "$bare_main" \
    --argjson prs "$prs" --argjson branches "$branch_count" \
    --argjson checkoutExists "$checkout_exists" --argjson dirty "$local_dirty" \
    --argjson bareExists "$bare_exists" \
    '{
      name:$name,repository:$repository,authority:"GITHUB_LIVE",liveMain:$liveMain,
      openPullRequests:$prs,openPullRequestCount:($prs|length),remoteBranchCount:$branches,
      localCheckout:{
        path:$checkoutPath,exists:$checkoutExists,authority:false,
        head:($localHead|select(length>0)//null),
        branch:($localBranch|select(length>0)//null),dirty:$dirty,
        cachedOriginMain:($localOrigin|select(length>0)//null),
        headMatchesLiveMain:($checkoutExists and $localHead==$liveMain),
        cachedOriginMatchesLiveMain:($checkoutExists and $localOrigin==$liveMain)
      },
      bareStore:{
        path:$barePath,exists:$bareExists,main:($bareMain|select(length>0)//null),
        mainMatchesLiveMain:($bareExists and $bareMain==$liveMain)
      }
    }')"
  repositories="$(jq --argjson item "$entry" '. + [$item]' <<<"$repositories")"
done

heartbeats="$(gh issue list -R "$CONTROL_REPO" --state open --limit 100 \
  --json number,title,updatedAt,body)"
exact="$(jq '[.[]|select(.title=="[TERMUX-AGENT] status")]' <<<"$heartbeats")"
count="$(jq 'length' <<<"$exact")"
number="$(jq -r 'if length==1 then .[0].number else empty end' <<<"$exact")"
updated="$(jq -r 'if length==1 then .[0].updatedAt else empty end' <<<"$exact")"
body="$(jq -r 'if length==1 then .[0].body else empty end' <<<"$exact")"
beat="$(sed -n 's/^heartbeat_utc:[[:space:]]*//p' <<<"$body" | head -n1)"
state="$(sed -n 's/^state:[[:space:]]*//p' <<<"$body" | head -n1)"

direct=SKIPPED native=SKIPPED
if [[ "${MORRO_STATUS_SKIP_TRANSPORTS:-0}" != 1 ]]; then
  d="$(bash "$SCRIPT_DIR/termux-remote-commanderctl.sh" status 2>&1 || true)"
  n="$(bash "$SCRIPT_DIR/termux-native-agentctl.sh" status 2>&1 || true)"
  grep -q '^paired=yes ' <<<"$d" && grep -q '^run: ' <<<"$d" \
    && direct=HEALTHY || direct=DEGRADED
  grep -q '^agent=RUNNING ' <<<"$n" && native=HEALTHY || native=DEGRADED
fi

jq -n \
  --arg observedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson repositories "$repositories" --argjson count "$count" \
  --arg number "$number" --arg updated "$updated" --arg beat "$beat" \
  --arg state "$state" --arg direct "$direct" --arg native "$native" \
  '{
    schemaVersion:1,kind:"MORRO_PROJECT_STATUS",observedAt:$observedAt,
    authority:"GITHUB_LIVE",repositories:$repositories,
    termux:{
      directCommander:$direct,nativeAgent:$native,
      heartbeat:{
        exactTitleOpenCount:$count,singleton:($count==1),
        issueNumber:($number|select(length>0)|tonumber?//null),
        updatedAt:($updated|select(length>0)//null),
        heartbeatUtc:($beat|select(length>0)//null),
        state:($state|select(length>0)//null)
      }
    }
  }'
