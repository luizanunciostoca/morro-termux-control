#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${TDP_REPO_URL:-https://github.com/luizanunciostoca/touristic-digital-platform.git}"
STORE="${TDP_BARE_STORE:-$HOME/repos/touristic-digital-platform.git}"
ROOT="${TDP_WORKTREE_ROOT:-$HOME/worktrees}"
META_ROOT="${TDP_WORKTREE_META_ROOT:-$ROOT/.morro-meta}"
DEFAULT_BRANCH="${TDP_DEFAULT_BRANCH:-main}"
LOCK_DIR="${STORE}.morro-lock"

fail() {
  echo "${1:-TDP_WORKTREE_ERROR}" >&2
  exit "${2:-1}"
}

require_token() {
  [[ "${1:-}" =~ ^[A-Za-z0-9._-]+$ ]] || fail "IDENTIFIER_INVALID:${1:-}"
}

require_ref() {
  [[ "${1:-}" =~ ^[A-Za-z0-9._/-]+$ ]] || fail "REF_INVALID:${1:-}"
  [[ "${1:-}" != *".."* ]] || fail "REF_TRAVERSAL_DENIED"
}

git_store() {
  git --git-dir="$STORE" "$@"
}
release_lock() {
  rm -rf "$LOCK_DIR"
}

acquire_lock() {
  mkdir -p "$(dirname "$STORE")"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    fail "WORKTREE_STORE_BUSY" 75
  fi
  printf 'pid=%s\nutc=%s\n' "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$LOCK_DIR/owner"
  trap release_lock EXIT INT TERM
}

ensure_store() {
  [[ -d "$STORE" ]] || fail "BARE_STORE_MISSING"
  [[ "$(git_store rev-parse --is-bare-repository)" == "true" ]] ||
    fail "BARE_STORE_INVALID"
  git_store remote get-url origin >/dev/null 2>&1 || fail "ORIGIN_MISSING"
}

fetch_main() {
  git_store fetch --filter=blob:none --prune origin     "+refs/heads/$DEFAULT_BRANCH:refs/heads/$DEFAULT_BRANCH"
}

bootstrap() {
  mkdir -p "$(dirname "$STORE")" "$ROOT" "$META_ROOT"
  acquire_lock
  if [[ ! -d "$STORE" ]]; then
    git init --bare "$STORE" >/dev/null
  fi
  if git_store remote get-url origin >/dev/null 2>&1; then
    git_store remote set-url origin "$REPO_URL"
  else
    git_store remote add origin "$REPO_URL"
  fi
  git_store config remote.origin.promisor true
  git_store config remote.origin.partialclonefilter blob:none
  git_store config remote.origin.fetch     "+refs/heads/$DEFAULT_BRANCH:refs/heads/$DEFAULT_BRANCH"
  fetch_main
  git_store symbolic-ref HEAD "refs/heads/$DEFAULT_BRANCH"
  echo "state=READY"
  echo "store=$STORE"
  echo "main=$(git_store rev-parse "refs/heads/$DEFAULT_BRANCH")"
}

refresh() {
  ensure_store
  acquire_lock
  fetch_main
  echo "main=$(git_store rev-parse "refs/heads/$DEFAULT_BRANCH")"
}

create_worktree() {
  local task="${1:-}" lease="${2:-}" ref="${3:-}" expected="${4:-}"
  require_token "$task"
  require_token "$lease"
  require_ref "$ref"
  [[ -z "$expected" || "$expected" =~ ^[0-9a-f]{40}$ ]] ||
    fail "EXPECTED_SHA_INVALID"
  ensure_store
  acquire_lock
  mkdir -p "$ROOT" "$META_ROOT"
  git_store fetch --filter=blob:none origin "$ref" >/dev/null
  local sha path name
  sha="$(git_store rev-parse 'FETCH_HEAD^{commit}')"
  [[ -z "$expected" || "$sha" == "$expected" ]] ||
    fail "EXACT_SHA_MISMATCH:expected=$expected:observed=$sha" 42
  name="${task}-${lease}-${sha:0:12}"
  path="$ROOT/$name"
  [[ ! -e "$path" ]] || fail "WORKTREE_REUSE_FORBIDDEN:$path" 43
  git_store worktree add --detach "$path" "$sha" >/dev/null
  printf '{"task":"%s","lease":"%s","sha":"%s","ref":"%s","path":"%s","createdAt":"%s"}\n'     "$task" "$lease" "$sha" "$ref" "$path" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"     >"$META_ROOT/$name.json"
  echo "state=CREATED"
  echo "path=$path"
  echo "sha=$sha"
}

retire_worktree() {
  local input="${1:-}"
  [[ -n "$input" ]] || fail "WORKTREE_PATH_REQUIRED"
  ensure_store
  acquire_lock
  local path root_real name dirty
  root_real="$(realpath -m "$ROOT")"
  path="$(realpath -m "$input")"
  [[ "$path" == "$root_real/"* ]] || fail "WORKTREE_PATH_OUTSIDE_ROOT"
  [[ -d "$path" ]] || fail "WORKTREE_MISSING:$path"
  name="$(basename "$path")"
  dirty="$(git -C "$path" status --porcelain --untracked-files=all)"
  if [[ -n "$dirty" ]]; then
    mkdir -p "$META_ROOT/quarantine"
    printf '{"state":"QUARANTINED","path":"%s","observedAt":"%s"}\n'       "$path" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"       >"$META_ROOT/quarantine/$name.json"
    echo "state=QUARANTINED"
    echo "path=$path"
    return 3
  fi
  git_store worktree remove "$path"
  rm -f "$META_ROOT/$name.json"
  git_store worktree prune
  echo "state=RETIRED"
  echo "path=$path"
}

compact_local_refs() {
  ensure_store
  acquire_lock
  local protected ref
  protected="refs/heads/$DEFAULT_BRANCH"
  while IFS= read -r ref; do
    [[ "$ref" == "$protected" ]] && continue
    if git_store worktree list --porcelain | grep -Fxq "branch $ref"; then
      continue
    fi
    git_store update-ref -d "$ref"
  done < <(git_store for-each-ref --format='%(refname)' refs/heads)
  git_store worktree prune
  echo "state=COMPACTED"
  echo "localHeads=$(git_store for-each-ref --format='%(refname)' refs/heads | wc -l)"
}

status_store() {
  ensure_store
  echo "state=READY"
  echo "store=$STORE"
  echo "main=$(git_store rev-parse "refs/heads/$DEFAULT_BRANCH")"
  echo "localHeads=$(git_store for-each-ref --format='%(refname)' refs/heads | wc -l)"
  git_store worktree list --porcelain
}

usage() {
  cat <<'EOF'
usage: tdp-worktreectl.sh <command> [args]
  bootstrap
  refresh
  create <task-id> <lease-id> <remote-ref> [expected-sha]
  retire <worktree-path>
  compact-local-refs
  status
EOF
}

case "${1:-}" in
  bootstrap) bootstrap ;;
  refresh) refresh ;;
  create) shift; create_worktree "$@" ;;
  retire) shift; retire_worktree "$@" ;;
  compact-local-refs) compact_local_refs ;;
  status) status_store ;;
  *) usage; exit 64 ;;
esac
