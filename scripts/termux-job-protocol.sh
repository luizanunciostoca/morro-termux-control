#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

MORRO_JOB_PROTOCOL_VERSION="2"
MORRO_PREFLIGHT_MARKER="MORRO_JOB_PREFLIGHT_V3"

morro_validate_request_file() {
  local request_file="$1"
  jq -e '
    type == "object" and
    .version == 2 and
    .confirm == "EXECUTE" and
    (.id | type == "string" and test("^[A-Za-z0-9._-]{1,128}$")) and
    (.target == "termux" or .target == "debian") and
    (.command | type == "string" and length > 0) and
    ((.cwd // "~") | type == "string" and length > 0) and
    ((.timeout_seconds // 900) | type == "number" and . >= 1 and . <= 3600)
  ' "$request_file" >/dev/null
}

morro_canonical_request_json() {
  local request_file="$1"
  morro_validate_request_file "$request_file"
  jq -cS . "$request_file"
}

morro_request_sha256() {
  local request_file="$1" canonical
  canonical="$(morro_canonical_request_json "$request_file")"
  printf '%s' "$canonical" | sha256sum | awk '{print $1}'
}

morro_preflight_marker() {
  local request_hash="$1"
  printf '%s\n\nprotocol_version: %s\nschema: PASS\nrequest_sha256: %s\n' \
    "$MORRO_PREFLIGHT_MARKER" "$MORRO_JOB_PROTOCOL_VERSION" "$request_hash"
}

morro_preflight_body_matches() {
  local body="$1" request_hash="$2"
  grep -Fxq "$MORRO_PREFLIGHT_MARKER" <<<"$body" &&
    grep -Fxq "protocol_version: $MORRO_JOB_PROTOCOL_VERSION" <<<"$body" &&
    grep -Fxq "schema: PASS" <<<"$body" &&
    grep -Fxq "request_sha256: $request_hash" <<<"$body"
}
