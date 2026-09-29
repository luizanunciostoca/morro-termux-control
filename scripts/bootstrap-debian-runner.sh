#!/usr/bin/env bash
set -Eeuo pipefail

REPO_SLUG="${REPO_SLUG:-luizanunciostoca/morro-termux-control}"
REPO_URL="${REPO_URL:-https://github.com/$REPO_SLUG}"
RUNNER_DIR="${RUNNER_DIR:-/root/morro-actions-runner}"
RUNNER_NAME="${RUNNER_NAME:-morro-sm-x820}"
RUNNER_LABELS="${RUNNER_LABELS:-morro-termux,sm-x820,debian-proot}"
RUNNER_TOKEN="${RUNNER_TOKEN:-}"

if [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
  echo "WARNING: expected ARM64/aarch64, got $(uname -m)" >&2
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script inside the Debian PRoot as root." >&2
  exit 77
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y   bash ca-certificates coreutils curl git gzip jq procps tar

mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

if [[ ! -x ./run.sh ]]; then
  release_json="$(mktemp)"
  curl --fail --silent --show-error --location     https://api.github.com/repos/actions/runner/releases/latest     -o "$release_json"

  asset_json="$(
    jq -c '
      [.assets[] |
       select(.name | test("^actions-runner-linux-arm64-[0-9.]+\\.tar\\.gz$"))][0]
    ' "$release_json"
  )"

  asset_url="$(jq -r '.browser_download_url // empty' <<<"$asset_json")"
  asset_name="$(jq -r '.name // empty' <<<"$asset_json")"
  asset_digest="$(jq -r '.digest // empty' <<<"$asset_json")"

  [[ -n "$asset_url" && -n "$asset_name" ]] || {
    echo "Could not resolve latest GitHub Actions ARM64 runner asset." >&2
    exit 69
  }

  echo "Downloading $asset_name"
  curl --fail --show-error --location "$asset_url" -o "$asset_name"

  if [[ "$asset_digest" == sha256:* ]]; then
    expected="${asset_digest#sha256:}"
    echo "$expected  $asset_name" | sha256sum -c -
  else
    echo "GitHub API did not publish an asset digest; TLS download completed but checksum was not available."
  fi

  tar xzf "$asset_name"
  rm -f "$asset_name" "$release_json"

  if [[ -x ./bin/installdependencies.sh ]]; then
    ./bin/installdependencies.sh || {
      echo "Runner dependency helper reported an error." >&2
      exit 69
    }
  fi
fi

cp "$(dirname "$0")/runner-loop.sh" "$RUNNER_DIR/runner-loop.sh"
chmod 700 "$RUNNER_DIR/runner-loop.sh"

export RUNNER_ALLOW_RUNASROOT=1

if [[ ! -f "$RUNNER_DIR/.runner" ]]; then
  if [[ -z "$RUNNER_TOKEN" ]]; then
    cat >&2 <<'EOF'
RUNNER_TOKEN is required for the first registration.

GitHub:
  repository -> Settings -> Actions -> Runners -> New self-hosted runner
  choose Linux + ARM64
  copy only the temporary registration token.

Then run:
  RUNNER_TOKEN='TOKEN_HERE' bash scripts/bootstrap-debian-runner.sh
EOF
    exit 78
  fi

  ./config.sh     --url "$REPO_URL"     --token "$RUNNER_TOKEN"     --name "$RUNNER_NAME"     --labels "$RUNNER_LABELS"     --work "_work"     --unattended     --replace
else
  echo "Runner is already configured; registration step skipped."
fi

rm -f "$RUNNER_DIR/.morro-stop"

echo
echo "Debian runner bootstrap complete."
echo "runner_dir=$RUNNER_DIR"
echo "runner_name=$RUNNER_NAME"
echo "labels=$RUNNER_LABELS"
echo
echo "Start test:"
echo "  cd $RUNNER_DIR && ./runner-loop.sh"
