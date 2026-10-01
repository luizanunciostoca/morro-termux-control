#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTL="$SCRIPT_DIR/tdp-worktreectl.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tdp-worktree-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

SRC="$TMP/source"
REMOTE="$TMP/remote.git"
export TDP_REPO_URL="$REMOTE"
export TDP_BARE_STORE="$TMP/store.git"
export TDP_WORKTREE_ROOT="$TMP/worktrees"
export TDP_WORKTREE_META_ROOT="$TMP/worktrees/.meta"

git init -q -b main "$SRC"
git -C "$SRC" config user.name "Morro Test"
git -C "$SRC" config user.email "morro-test@example.invalid"
printf 'one\n' >"$SRC/file.txt"
git -C "$SRC" add file.txt
git -C "$SRC" commit -q -m initial
git clone -q --bare "$SRC" "$REMOTE"
SHA="$(git -C "$SRC" rev-parse HEAD)"

"$CTL" bootstrap >/dev/null
[[ "$(git --git-dir="$TDP_BARE_STORE" rev-parse --is-bare-repository)" == "true" ]]
[[ "$(git --git-dir="$TDP_BARE_STORE" rev-parse refs/heads/main)" == "$SHA" ]]
OUT="$("$CTL" create MD-TEST lease1 refs/heads/main "$SHA")"
PATH_ONE="$(sed -n 's/^path=//p' <<<"$OUT")"
[[ -f "$PATH_ONE/file.txt" ]]
[[ "$(git -C "$PATH_ONE" rev-parse HEAD)" == "$SHA" ]]

set +e
"$CTL" create MD-TEST lease1 refs/heads/main "$SHA" >"$TMP/reuse.out" 2>&1
CODE="$?"
set -e
[[ "$CODE" -eq 43 ]]
grep -q "WORKTREE_REUSE_FORBIDDEN" "$TMP/reuse.out"

BAD_SHA="$(printf '0%.0s' {1..40})"
set +e
"$CTL" create MD-TEST wrong refs/heads/main "$BAD_SHA" >"$TMP/sha.out" 2>&1
CODE="$?"
set -e
[[ "$CODE" -eq 42 ]]
grep -q "EXACT_SHA_MISMATCH" "$TMP/sha.out"

"$CTL" retire "$PATH_ONE" >/dev/null
[[ ! -e "$PATH_ONE" ]]
OUT="$("$CTL" create MD-TEST lease2 refs/heads/main "$SHA")"
PATH_TWO="$(sed -n 's/^path=//p' <<<"$OUT")"
printf 'dirty\n' >"$PATH_TWO/untracked.txt"

set +e
"$CTL" retire "$PATH_TWO" >"$TMP/quarantine.out" 2>&1
CODE="$?"
set -e
[[ "$CODE" -eq 3 ]]
grep -q "state=QUARANTINED" "$TMP/quarantine.out"
[[ -d "$PATH_TWO" ]]
[[ -f "$TDP_WORKTREE_META_ROOT/quarantine/$(basename "$PATH_TWO").json" ]]

rm "$PATH_TWO/untracked.txt"
"$CTL" retire "$PATH_TWO" >/dev/null
[[ ! -e "$PATH_TWO" ]]

git --git-dir="$TDP_BARE_STORE" update-ref refs/heads/stale "$SHA"
"$CTL" compact-local-refs >/dev/null
git --git-dir="$TDP_BARE_STORE" show-ref --verify --quiet refs/heads/main
! git --git-dir="$TDP_BARE_STORE" show-ref --verify --quiet refs/heads/stale

echo "TDP_WORKTREECTL_TEST_PASS"
