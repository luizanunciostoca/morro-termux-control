#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/morro-project-status-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"

cat >"$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
case "$args" in
  "api repos/luizanunciostoca/touristic-digital-platform/commits/main --jq .sha")
    printf '%040d\n' 1 ;;
  "api repos/luizanunciostoca/morro-integration-lab/commits/main --jq .sha")
    printf '%040d\n' 2 ;;
  "api repos/luizanunciostoca/morro-termux-control/commits/main --jq .sha")
    printf '%040d\n' 3 ;;
  "pr list -R luizanunciostoca/touristic-digital-platform --state open --limit 100 --json number,title,headRefName,headRefOid,baseRefName,isDraft,updatedAt")
    printf '%s\n' '[{"number":9,"title":"candidate","headRefName":"feat/x","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","baseRefName":"main","isDraft":false,"updatedAt":"2026-10-01T00:00:00Z"}]' ;;
  "pr list -R luizanunciostoca/morro-integration-lab --state open --limit 100 --json number,title,headRefName,headRefOid,baseRefName,isDraft,updatedAt"|"pr list -R luizanunciostoca/morro-termux-control --state open --limit 100 --json number,title,headRefName,headRefOid,baseRefName,isDraft,updatedAt")
    printf '%s\n' '[]' ;;
  "issue list -R luizanunciostoca/morro-termux-control --state open --limit 100 --json number,title,updatedAt,body")
    printf '%s\n' '[{"number":4,"title":"[TERMUX-AGENT] status","updatedAt":"2026-10-01T14:00:01Z","body":"MORRO_NATIVE_AGENT_V3\nstate: ONLINE\nheartbeat_utc: 2026-10-01T14:00:00Z"}]' ;;
  *)
    echo "UNEXPECTED_GH_CALL:$args" >&2
    exit 97 ;;
esac
GH
chmod +x "$TMP/bin/gh"

PATH="$TMP/bin:$PATH" \
MORRO_STATUS_HOME="$TMP/home" \
MORRO_STATUS_SKIP_TRANSPORTS=1 \
bash "$SCRIPT_DIR/morro-project-status.sh" --json >"$TMP/status.json"

jq -e '
  .schemaVersion==1 and
  .kind=="MORRO_PROJECT_STATUS" and
  .authority=="GITHUB_LIVE" and
  (.repositories|length)==3 and
  (.repositories[0].name=="platform") and
  (.repositories[0].openPullRequestCount==1) and
  (.repositories|all(.localCheckout.exists==false)) and
  (.termux.heartbeat.singleton==true) and
  (.termux.heartbeat.issueNumber==4) and
  (.termux.heartbeat.state=="ONLINE") and
  (.termux.directCommander=="SKIPPED") and
  (.termux.nativeAgent=="SKIPPED")
' "$TMP/status.json" >/dev/null

echo "MORRO_PROJECT_STATUS_TEST_PASS"
