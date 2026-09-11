#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DISPATCH_REF="$REPO_ROOT/skills/flow-common/references/review-dispatch.md"
HELPER="$REPO_ROOT/scripts/review-singleflight.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
PASS=0
FAIL=0

record_result() {
  if [[ "$2" -eq 0 ]]; then echo "PASS: $1"; ((PASS++)) || true; else echo "FAIL: $1"; ((FAIL++)) || true; fi
}

SNIPPET="$TEST_ROOT/dispatch-snippet.sh"
awk '/^review_hard_dispatch\(\) \{/{inside=1} inside{print} inside && /^review_hard_dispatch$/{exit}' "$DISPATCH_REF" > "$SNIPPET"
[[ -s "$SNIPPET" ]]

run_dispatch() {
  local backend="$1" pr="$2"
  OWNER=owner REPO=repo PR_NUM="$pr" HEAD_SHA=abc123 FORGE_HOST=github.com \
    REVIEW_HARD_BACKEND="$backend" XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
    REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_FS_TYPE=overlay REVIEW_SINGLEFLIGHT_NOW=100 \
    bash "$SNIPPET"
}

mkdir -p "$TEST_ROOT/runtime"
EXPECTED_KEY=$'github.com\nowner/repo\n41'
set +e
FIRST_OUTPUT="$(run_dispatch codex 41 2>"$TEST_ROOT/first.err")"
FIRST_RC=$?
set -e
FIRST_HANDOFF="$(awk '/^review-dispatch handoff: /{sub(/^review-dispatch handoff: /,"",$0); path=$0} END{print path}' <<<"$FIRST_OUTPUT")"
FIRST_TMPDIR="$(jq -r '.tmpdir // empty' <<<"$FIRST_HANDOFF" 2>/dev/null || true)"
FIRST_STATE="$(jq -r '.dispatch_state // empty' <<<"$FIRST_HANDOFF" 2>/dev/null || true)"
FIRST_SINGLEFLIGHT="$(jq -r '.singleflight // empty' <<<"$FIRST_HANDOFF" 2>/dev/null || true)"
FIRST_LEASE="$(jq -r '.lease_id // empty' <<<"$FIRST_HANDOFF" 2>/dev/null || true)"
if [[ "$FIRST_RC" -eq 0 && -n "$FIRST_HANDOFF" ]] \
  && jq -e --arg key "$EXPECTED_KEY" --arg tmpdir "$FIRST_TMPDIR" --arg state "$FIRST_STATE" --arg lease "$FIRST_LEASE" \
    '.backend == "codex" and .canonical_key == $key and .tmpdir == $tmpdir and .dispatch_state == $state and .lease_id == $lease' \
    <<<"$FIRST_HANDOFF" >/dev/null \
  && [[ -d "$FIRST_TMPDIR" && -r "$FIRST_STATE" && -r "$FIRST_SINGLEFLIGHT" ]] \
  && jq -e --arg lease "$FIRST_LEASE" '.per_pr.acquired == true and .per_pr.lease_id == $lease and .post_state == "in_progress"' "$FIRST_STATE" >/dev/null \
  && jq -e --arg key "$EXPECTED_KEY" --arg tmpdir "$FIRST_TMPDIR" --arg state "$FIRST_STATE" --arg lease "$FIRST_LEASE" \
    '.scope == "per_pr" and .canonical_key == $key and .tmpdir == $tmpdir and .lease_file_ref == $state and .lease_id == $lease' \
    "$FIRST_SINGLEFLIGHT" >/dev/null; then result=0; else result=1; fi
record_result "acquire 成功時に managed handoff と singleflight/state を返す" "$result"

set +e
SECOND_OUTPUT="$(run_dispatch codex 41 2>"$TEST_ROOT/second.err")"
SECOND_RC=$?
set -e
SECOND_RESULT="$(awk '/^review-dispatch result: /{sub(/^review-dispatch result: /,"",$0); path=$0} END{print path}' <<<"$SECOND_OUTPUT")"
if [[ "$SECOND_RC" -eq 2 && -s "$SECOND_RESULT" ]] \
  && jq -e '.dispatch_status == "unavailable" and .post_state == "not_applicable" and (.failure_reason | length) > 0' "$SECOND_RESULT" >/dev/null; then result=0; else result=1; fi
record_result "acquire 競合時に fail-fast envelope を返して engine/post へ進まない" "$result"

RELEASE_RC=0
if [[ -n "$FIRST_LEASE" && -r "$FIRST_TMPDIR/sf-owner-token" ]]; then
  XDG_RUNTIME_DIR="$TEST_ROOT/runtime" REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_FS_TYPE=overlay REVIEW_SINGLEFLIGHT_NOW=100 \
    bash "$HELPER" release --scope per_pr --key "$EXPECTED_KEY" --owner-token-file "$FIRST_TMPDIR/sf-owner-token" \
    --lease-id "$FIRST_LEASE" >/dev/null || RELEASE_RC=$?
else
  RELEASE_RC=1
fi
record_result "handoff 後のテスト lease を明示的に release できる" "$RELEASE_RC"

TOKEN="$TEST_ROOT/fence-token"
(umask 077; printf '%s\n' fence-token-secure > "$TOKEN")
chmod 600 "$TOKEN"
KEY=$'github.com\nowner/fence\n43'
ACQUIRE="$(XDG_RUNTIME_DIR="$TEST_ROOT/runtime" REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_FS_TYPE=overlay REVIEW_SINGLEFLIGHT_NOW=100 bash "$HELPER" acquire --scope per_pr --key "$KEY" --owner-token-file "$TOKEN" --engine codex-hard --head-sha abc123 --overdue-seconds 100)"
LEASE_ID="$(jq -r '.lease_id' <<<"$ACQUIRE")"
XDG_RUNTIME_DIR="$TEST_ROOT/runtime" REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_FS_TYPE=overlay REVIEW_SINGLEFLIGHT_NOW=100 bash "$HELPER" release --force-release --scope per_pr --key "$KEY" --expected-lease-id "$LEASE_ID" --reason test >/dev/null
MUTATIONS="$TEST_ROOT/mutations"
: > "$MUTATIONS"
set +e
VERIFY_OUT="$(XDG_RUNTIME_DIR="$TEST_ROOT/runtime" REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_FS_TYPE=overlay REVIEW_SINGLEFLIGHT_NOW=100 bash "$HELPER" verify --scope per_pr --key "$KEY" --owner-token-file "$TOKEN" --lease-id "$LEASE_ID" 2>/dev/null)"
VERIFY_RC=$?
set -e
if [[ "$VERIFY_RC" -eq 3 && "$VERIFY_OUT" == *'"state":"not_owner"'* && ! -s "$MUTATIONS" ]]; then result=0; else result=1; fi
record_result "phase 中の force-release 後は verify 失敗で mutation を停止する" "$result"

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
[[ "$FAIL" -eq 0 ]]
