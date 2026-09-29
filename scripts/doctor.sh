#!/usr/bin/env bash
set -Eeuo pipefail

echo "=== MORRO TERMUX RUNNER DOCTOR ==="
echo "utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "user=$(id -un)"
echo "uid=$(id -u)"
echo "home=$HOME"
echo "pwd=$PWD"
echo "kernel=$(uname -srmo)"
echo "machine=$(uname -m)"
echo "github_actions=${GITHUB_ACTIONS:-false}"
echo "runner_name=${RUNNER_NAME:-unknown}"
echo "runner_arch=${RUNNER_ARCH:-unknown}"
echo "runner_os=${RUNNER_OS:-unknown}"

for cmd in bash git curl jq timeout node npm python3 java adb gh; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '%-10s %s\n' "$cmd" "$(command -v "$cmd")"
  else
    printf '%-10s %s\n' "$cmd" "MISSING"
  fi
done

if command -v git >/dev/null 2>&1; then
  git --version
fi
if command -v node >/dev/null 2>&1; then
  node --version
fi
if command -v python3 >/dev/null 2>&1; then
  python3 --version
fi

echo "disk:"
df -h "$HOME" | tail -n +1

echo "memory:"
free -h 2>/dev/null || true

echo "doctor=PASS"
