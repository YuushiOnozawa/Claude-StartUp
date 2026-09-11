#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POST_REF="$REPO_ROOT/skills/flow-common/references/review-post.md"
HELPER="$REPO_ROOT/scripts/review-singleflight.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
PASS=0
FAIL=0

record_result() {
  if [[ "$2" -eq 0 ]]; then echo "PASS: $1"; ((PASS++)) || true; else echo "FAIL: $1"; ((FAIL++)) || true; fi
}
extract_post() {
  awk 'index($0,"## 実行手順")==1{found=1;next} found&&/^```bash$/{in_block=1;next} found&&in_block&&/^```$/{exit} found&&in_block{print}' \
    "$POST_REF" >"$TEST_ROOT/review-post.sh"
  chmod +x "$TEST_ROOT/review-post.sh"
}
make_token_and_lease() {
  mkdir -p "$TEST_ROOT/dispatch" "$TEST_ROOT/runtime" "$TEST_ROOT/bin"
  chmod 700 -- "$TEST_ROOT/dispatch"
  (umask 077; printf '%s\n' fencing-token-secure >"$TEST_ROOT/dispatch/sf-owner-token")
  chmod 600 -- "$TEST_ROOT/dispatch/sf-owner-token"
  LEASE_JSON="$(REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_NOW=100 XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
    bash "$HELPER" acquire --scope per_pr --key "$KEY" --owner-token-file "$TEST_ROOT/dispatch/sf-owner-token" \
    --engine magi-hard --overdue-seconds 100)"
  LEASE_ID="$(jq -r .lease_id <<<"$LEASE_JSON")"
  jq -n --arg token_file "$TEST_ROOT/dispatch/sf-owner-token" --arg lease_id "$LEASE_ID" \
    '{schema_version:1,owner_token_file:$token_file,per_pr:{acquired:true,lease_id:$lease_id}}' \
    >"$TEST_ROOT/dispatch/dispatch-state.json"
  chmod 600 -- "$TEST_ROOT/dispatch/dispatch-state.json"
}
make_request() {
  local path="$1" lease_id="$2"
  jq -n --arg lease_id "$lease_id" --arg tmpdir "$TEST_ROOT/dispatch" --arg token "$TEST_ROOT/dispatch/sf-owner-token" \
    --arg state "$TEST_ROOT/dispatch/dispatch-state.json" --arg key "$KEY" --arg diff "$TEST_ROOT/diff" \
    --arg result "$TEST_ROOT/$path.result.json" \
    '{schema_version:"1",artifact_type:"review-post-request",engine:"magi",forge_host:"github.com",
      pr:{owner:"owner",repo:"repo",number:7,head_sha:"abc123"},
      inputs:{findings_artifact:null,adjudication_result:null,diff:$diff},
      engine_state:{post_inline:false,block_layer:"structure",audit_note:null,importance_note:null,
        artifact_note:null,normalized_results:"raw report",finding_list:null},
      singleflight:{managed_by:"review-hard",tmpdir:$tmpdir,owner_token_file:$token,lease_file_ref:$state,
        scope:"per_pr",canonical_key:$key,lease_id:$lease_id,forge_host:"github.com"},result_path:$result}' \
    >"$TEST_ROOT/$path.request.json"
}

KEY=$'github.com\nowner/repo\n7'
extract_post
printf '%s\n' diff >"$TEST_ROOT/diff"
mkdir -p "$TEST_ROOT/bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'method=GET endpoint=""' \
  'for arg in "$@"; do' \
  '  case "$arg" in' \
  '    -X) next_method=true ;;' \
  '    -f|-F|--jq) next_value=true ;;' \
  '    *) if [[ "${next_method:-false}" == true ]]; then method="${arg^^}"; next_method=false; continue; fi' \
  '       if [[ "${next_value:-false}" == true ]]; then next_value=false; continue; fi' \
  '       [[ "$arg" == user || "$arg" == repos/* ]] && endpoint="$arg" ;;' \
  '  esac' \
  'done' \
  'kind=other' \
  '[[ "$endpoint" == user ]] && kind=user' \
  '[[ "$endpoint" == *"/issues/"*"/comments?"* ]] && kind=issue-list' \
  '[[ "$endpoint" == *"/pulls/"*"/comments?"* ]] && kind=pull-list' \
  '[[ "$method" == POST && "$endpoint" == *"/issues/"*"/comments" ]] && kind=summary-post' \
  'printf "%s:%s\\n" "$method" "$kind" >>"$GH_EVENT_LOG"' \
  'case "$kind" in' \
  '  user) printf "%s\\n" review-bot ;;' \
  '  issue-list|pull-list) printf "%s\\n" "[]" ;;' \
  '  summary-post) sleep "${GH_POST_DELAY:-0}"; printf "%s\\n" https://stub.invalid/summary ;;' \
  '  *) exit 2 ;;' \
  'esac' >"$TEST_ROOT/bin/gh"
chmod +x "$TEST_ROOT/bin/gh"

make_token_and_lease
make_request valid "$LEASE_ID"
: >"$TEST_ROOT/events.log"
env PATH="$TEST_ROOT/bin:$PATH" GH_EVENT_LOG="$TEST_ROOT/events.log" XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
  REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_NOW=100 \
  bash "$TEST_ROOT/review-post.sh" "$TEST_ROOT/valid.request.json" >"$TEST_ROOT/valid.out" 2>"$TEST_ROOT/valid.err"
if grep -Fq 'POST:summary-post' "$TEST_ROOT/events.log" \
  && jq -e '.last_checkpoint_at == 100' "$TEST_ROOT/runtime/claude-review-sf/per_pr/"*.json >/dev/null 2>&1; then result=0; else result=1; fi
record_result "managed request は post lock と mutation 直前 renew を有効化する" "$result"

make_request invalid "$LEASE_ID-wrong"
: >"$TEST_ROOT/events.log"
set +e
env PATH="$TEST_ROOT/bin:$PATH" GH_EVENT_LOG="$TEST_ROOT/events.log" XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
  REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_NOW=100 \
  bash "$TEST_ROOT/review-post.sh" "$TEST_ROOT/invalid.request.json" >"$TEST_ROOT/invalid.out" 2>"$TEST_ROOT/invalid.err"
INVALID_RC=$?
set -e
if [[ "$INVALID_RC" -eq 2 && ! -s "$TEST_ROOT/events.log" ]] \
  && grep -Fq 'managed lease admission failure' "$TEST_ROOT/invalid.err"; then result=0; else result=1; fi
record_result "managed lease_id 不一致は GitHub API 前に exit 2 で停止する" "$result"

RELEASE_OUT="$(REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_NOW=100 XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
  bash "$HELPER" release --scope per_pr --key "$KEY" --owner-token-file "$TEST_ROOT/dispatch/sf-owner-token" --lease-id "$LEASE_ID")"
: >"$TEST_ROOT/events.log"
make_request released "$LEASE_ID"
set +e
env PATH="$TEST_ROOT/bin:$PATH" GH_EVENT_LOG="$TEST_ROOT/events.log" XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
  REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_NOW=100 \
  bash "$TEST_ROOT/review-post.sh" "$TEST_ROOT/released.request.json" >"$TEST_ROOT/released.out" 2>"$TEST_ROOT/released.err"
RELEASED_RC=$?
set -e
if [[ "$RELEASED_RC" -eq 2 && ! -s "$TEST_ROOT/events.log" ]]; then result=0; else result=1; fi
record_result "released lease は旧 owner を GitHub write 前に fence する" "$result"

if bash -n "$TEST_ROOT/review-post.sh"; then result=0; else result=1; fi
record_result "managed review-post 実行コードの構文が正しい" "$result"

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
[[ "$FAIL" -eq 0 ]]
