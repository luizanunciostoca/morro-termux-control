#!/usr/bin/env bash
set -Eeuo pipefail

RUNNER_DIR="${RUNNER_DIR:-/root/morro-actions-runner}"
STOP_FILE="$RUNNER_DIR/.morro-stop"
LOG_DIR="$RUNNER_DIR/logs"

mkdir -p "$LOG_DIR"
cd "$RUNNER_DIR"

export RUNNER_ALLOW_RUNASROOT=1

echo "[morro-runner] loop started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

while true; do
  if [[ -f "$STOP_FILE" ]]; then
    echo "[morro-runner] stop marker detected"
    exit 0
  fi

  echo "[morro-runner] starting GitHub runner"
  set +e
  ./run.sh 2>&1 | tee -a "$LOG_DIR/runner.log"
  rc=${PIPESTATUS[0]}
  set -e

  if [[ -f "$STOP_FILE" ]]; then
    echo "[morro-runner] stopped intentionally"
    exit 0
  fi

  echo "[morro-runner] runner exited rc=$rc; restarting in 10s"
  sleep 10
done
