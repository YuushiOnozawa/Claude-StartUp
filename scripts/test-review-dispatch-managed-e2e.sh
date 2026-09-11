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

# acquire 時点で chunk/persona 数が未確定なら codex の max_configured_allowance を使う。
set +e
FALLBACK_OUTPUT="$(env -u SF_CHUNK_COUNT -u DIFF_CHUNK_COUNT -u SF_PERSONA_COUNT \
  OWNER=owner REPO=repo PR_NUM=42 HEAD_SHA=abc123 FORGE_HOST=github.com \
  REVIEW_HARD_BACKEND=codex XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
  REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_FS_TYPE=overlay REVIEW_SINGLEFLIGHT_NOW=100 \
  bash "$SNIPPET" 2>"$TEST_ROOT/fallback.err")"
FALLBACK_RC=$?
set -e
FALLBACK_HANDOFF="$(awk '/^review-dispatch handoff: /{sub(/^review-dispatch handoff: /,"",$0); path=$0} END{print path}' <<<"$FALLBACK_OUTPUT")"
FALLBACK_TMPDIR="$(jq -r '.tmpdir // empty' <<<"$FALLBACK_HANDOFF" 2>/dev/null || true)"
FALLBACK_KEY=$'github.com\nowner/repo\n42'
FALLBACK_HASH="$(printf 'per_pr\0%s' "$FALLBACK_KEY" | sha256sum | cut -d' ' -f1)"
CODEX_MAX_ALLOWANCE="$(bash "$REPO_ROOT/skills/flow-common/execution-budget.sh" max-allowance codex)"
if [[ "$FALLBACK_RC" -eq 0 && -n "$FALLBACK_TMPDIR" ]] \
  && jq -e --argjson expected "$CODEX_MAX_ALLOWANCE" \
    '.planned_overdue_at == $expected' "$TEST_ROOT/runtime/claude-review-sf/per_pr/$FALLBACK_HASH.json" >/dev/null; then
  result=0
else
  result=1
fi
record_result "chunk/persona 未確定時の codex planned_overdue_at は max_configured_allowance を使う" "$result"
FALLBACK_LEASE="$(jq -r '.lease_id // empty' <<<"$FALLBACK_HANDOFF" 2>/dev/null || true)"
if [[ -n "$FALLBACK_LEASE" ]]; then
  XDG_RUNTIME_DIR="$TEST_ROOT/runtime" REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_FS_TYPE=overlay REVIEW_SINGLEFLIGHT_NOW=100 \
    bash "$HELPER" release --scope per_pr --key "$FALLBACK_KEY" --owner-token-file "$FALLBACK_TMPDIR/sf-owner-token" \
    --lease-id "$FALLBACK_LEASE" >/dev/null
fi

# acquire 後の dispatch-state 更新失敗は handoff を返さず、取得済み lease を release する。
STATE_FAIL_HELPER="$TEST_ROOT/state-fail-after-acquire.sh"
cat >"$STATE_FAIL_HELPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == *'.per_pr.acquired=true'* ]]; then
  state_path=""
  while ((\$#)); do
    if [[ "\$1" == "--dispatch-state" && \$# -ge 2 ]]; then
      state_path="\$2"
      break
    fi
    shift
  done
  printf '%s\n' "\$state_path" > "$TEST_ROOT/failure-state-path"
  echo 'injected state update failure' >&2
  exit 19
fi
exec bash "$REPO_ROOT/scripts/review-dispatch-state.sh" "\$@"
EOF
chmod 700 -- "$STATE_FAIL_HELPER"
FAILURE_KEY=$'github.com\nowner/repo\n44'
set +e
FAILURE_OUTPUT="$(OWNER=owner REPO=repo PR_NUM=44 HEAD_SHA=abc123 FORGE_HOST=github.com \
  REVIEW_HARD_BACKEND=codex STATE_HELPER="$STATE_FAIL_HELPER" XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
  REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_FS_TYPE=overlay REVIEW_SINGLEFLIGHT_NOW=100 \
  bash "$SNIPPET" 2>"$TEST_ROOT/state-failure.err")"
FAILURE_RC=$?
set -e
FAILURE_STATE="$(<"$TEST_ROOT/failure-state-path")"
REACQUIRE_TOKEN="$TEST_ROOT/reacquire-token"
(umask 077; printf '%s\n' reacquire-token-secure >"$REACQUIRE_TOKEN")
chmod 600 -- "$REACQUIRE_TOKEN"
set +e
REACQUIRE_OUTPUT="$(XDG_RUNTIME_DIR="$TEST_ROOT/runtime" REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_FS_TYPE=overlay REVIEW_SINGLEFLIGHT_NOW=100 \
  bash "$HELPER" acquire --scope per_pr --key "$FAILURE_KEY" --owner-token-file "$REACQUIRE_TOKEN" \
  --engine codex-hard --overdue-seconds 100 2>"$TEST_ROOT/reacquire.err")"
REACQUIRE_RC=$?
set -e
if [[ "$FAILURE_RC" -eq 5 && ! "$FAILURE_OUTPUT" =~ 'review-dispatch handoff:' \
  && -s "$FAILURE_STATE" ]] \
  && jq -e '.per_pr.acquired == false and .saved_rc == 5 and .phase == "aborted"' "$FAILURE_STATE" >/dev/null \
  && [[ "$REACQUIRE_RC" -eq 0 && "$(jq -r '.state' <<<"$REACQUIRE_OUTPUT")" == acquired ]]; then
  result=0
else
  result=1
fi
record_result "acquire 後の state 更新失敗は lease を release して handoff を返さない" "$result"
REACQUIRE_LEASE="$(jq -r '.lease_id // empty' <<<"$REACQUIRE_OUTPUT")"
if [[ -n "$REACQUIRE_LEASE" ]]; then
  XDG_RUNTIME_DIR="$TEST_ROOT/runtime" REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_FS_TYPE=overlay REVIEW_SINGLEFLIGHT_NOW=100 \
    bash "$HELPER" release --scope per_pr --key "$FAILURE_KEY" --owner-token-file "$REACQUIRE_TOKEN" \
    --lease-id "$REACQUIRE_LEASE" >/dev/null
fi

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
