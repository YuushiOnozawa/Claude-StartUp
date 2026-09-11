#!/usr/bin/env bash
# review-post の opt-in post lock と dedup→write 原子区間の契約テスト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POST_REF="$REPO_ROOT/skills/flow-common/references/review-post.md"
PASS=0
FAIL=0
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

record_result() {
  if [[ "$2" -eq 0 ]]; then
    echo "PASS: $1"
    ((PASS++)) || true
  else
    echo "FAIL: $1"
    ((FAIL++)) || true
  fi
}

POST_SCRIPT="$TEST_ROOT/review-post.sh"
awk '
  index($0, "## 実行手順") == 1 { found=1; next }
  found && /^```bash$/ { in_block=1; next }
  found && in_block && /^```$/ { exit }
  found && in_block { print }
' "$POST_REF" >"$POST_SCRIPT"

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/runtime" "$TEST_ROOT/default-runtime"
cat >"$TEST_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
method=GET
endpoint=""
body=""
take_method=false
take_field=false
take_jq=false
for arg in "$@"; do
  if [[ "$take_method" == true ]]; then method="${arg^^}"; take_method=false; continue; fi
  if [[ "$take_field" == true ]]; then
    [[ "$arg" == body=* ]] && body="${arg#body=}"
    take_field=false
    continue
  fi
  if [[ "$take_jq" == true ]]; then take_jq=false; continue; fi
  case "$arg" in
    -X) take_method=true ;;
    -f|-F) take_field=true ;;
    --jq) take_jq=true ;;
    user|repos/*) endpoint="$arg" ;;
  esac
done
kind=other
[[ "$endpoint" == user ]] && kind=user
[[ "$endpoint" == *'/issues/'*'/comments?'* ]] && kind=issue-list
[[ "$endpoint" == *'/pulls/'*'/comments?'* ]] && kind=pull-list
[[ "$endpoint" == *'/issues/comments/'* ]] && kind=summary-patch
[[ "$method" == POST && "$endpoint" == *'/issues/'*'/comments' ]] && kind=summary-post
printf '%s:%s:%s\n' "$method" "$kind" "${PUBLISHER_ID:-unknown}" >>"$GH_EVENT_LOG"

if [[ "$method" == GET && "$kind" == user ]]; then
  printf '%s\n' 'review-bot'
elif [[ "$method" == GET && "$kind" == issue-list ]]; then
  if [[ -s "$GH_STATE" ]]; then cat "$GH_STATE"; else printf '%s\n' '[]'; fi
elif [[ "$method" == GET && "$kind" == pull-list ]]; then
  printf '%s\n' '[]'
elif [[ "$method" == POST && "$kind" == summary-post ]]; then
  sleep "${GH_POST_DELAY:-0}"
  jq -n --arg body "$body" '[{id:1,body:$body,user:{login:"review-bot"}}]' >"$GH_STATE"
  printf '%s\n' 'https://stub.invalid/post'
elif [[ "$method" == PATCH && "$kind" == summary-patch ]]; then
  jq -n --arg body "$body" '[{id:1,body:$body,user:{login:"review-bot"}}]' >"$GH_STATE"
  printf '%s\n' 'https://stub.invalid/patch'
else
  exit 2
fi
EOF
chmod +x "$TEST_ROOT/bin/gh"

cat >"$TEST_ROOT/budget.json" <<'EOF'
{"phases":{"review_post":{"magi":5,"codex":5,"breakdown":{"api_timeout_seconds":2,"page_limit":2,"inline_posts_soft_seconds":2}}}}
EOF
cat >"$TEST_ROOT/short-budget.json" <<'EOF'
{"phases":{"review_post":{"magi":5,"codex":1,"breakdown":{"api_timeout_seconds":2,"page_limit":2,"inline_posts_soft_seconds":2}}}}
EOF

printf '%s\n' 'diff' >"$TEST_ROOT/pr.diff"
write_request() {
  local result="$1" request="$2" engine="${3:-magi}" owner="${4:-Owner}" repo="${5:-Repo}" host="${6:-github.com}"
  jq -n --arg diff "$TEST_ROOT/pr.diff" --arg result "$result" --arg engine "$engine" \
    --arg owner "$owner" --arg repo "$repo" --arg host "$host" \
    '{schema_version:"1",artifact_type:"review-post-request",engine:$engine,forge_host:$host,
      pr:{owner:$owner,repo:$repo,number:7,head_sha:"abc123"},
      inputs:{findings_artifact:null,adjudication_result:null,diff:$diff},
      engine_state:{post_inline:false,block_layer:"structure",audit_note:null,importance_note:null,
        artifact_note:null,normalized_results:"raw report",finding_list:null},result_path:$result}' >"$request"
}
lock_path() {
  local owner="$1" repo="$2" host="${3:-github.com}" prefix hash
  prefix="$(printf '%s-%s-7' "${owner,,}" "${repo,,}" | tr -cs 'a-z0-9._-' '-' | cut -c1-48)"
  hash="$(printf '%s\0%s/%s\0%s' "$host" "${owner,,}" "${repo,,}" 7 | sha256sum | cut -d' ' -f1)"
  printf '%s/runtime/claude-review-post-%s-%s.lock' "$TEST_ROOT" "$prefix" "$hash"
}
write_request "$TEST_ROOT/result-one.json" "$TEST_ROOT/request-one.json"
write_request "$TEST_ROOT/result-two.json" "$TEST_ROOT/request-two.json"

: >"$TEST_ROOT/events.log"
rm -f -- "$TEST_ROOT/comments.json"
COMMON_ENV=(
  "PATH=$TEST_ROOT/bin:$PATH"
  "GH_EVENT_LOG=$TEST_ROOT/events.log"
  "GH_STATE=$TEST_ROOT/comments.json"
  "EXECUTION_BUDGET_JSON=$TEST_ROOT/budget.json"
  "XDG_RUNTIME_DIR=$TEST_ROOT/runtime"
  "REVIEW_POST_USE_LOCK=1"
)
env "${COMMON_ENV[@]}" PUBLISHER_ID=one GH_POST_DELAY=1 \
  bash "$POST_SCRIPT" "$TEST_ROOT/request-one.json" >"$TEST_ROOT/one.out" 2>"$TEST_ROOT/one.err" &
FIRST_PID=$!
for _ in $(seq 1 50); do
  grep -Fq 'POST:summary-post:one' "$TEST_ROOT/events.log" 2>/dev/null && break
  sleep 0.05
done
env "${COMMON_ENV[@]}" PUBLISHER_ID=two GH_POST_DELAY=0 \
  bash "$POST_SCRIPT" "$TEST_ROOT/request-two.json" >"$TEST_ROOT/two.out" 2>"$TEST_ROOT/two.err" &
SECOND_PID=$!
wait "$FIRST_PID"
wait "$SECOND_PID"

POST_COUNT="$(grep -c '^POST:summary-post:' "$TEST_ROOT/events.log" || true)"
PATCH_COUNT="$(grep -c '^PATCH:summary-patch:' "$TEST_ROOT/events.log" || true)"
FIRST_POST_LINE="$(grep -n '^POST:summary-post:one$' "$TEST_ROOT/events.log" | cut -d: -f1)"
SECOND_GET_LINE="$(grep -n '^GET:issue-list:two$' "$TEST_ROOT/events.log" | cut -d: -f1)"
if [[ "$POST_COUNT" -eq 1 && "$PATCH_COUNT" -eq 1 \
  && "$FIRST_POST_LINE" -lt "$SECOND_GET_LINE" ]]; then result=0; else result=1; fi
record_result "post lock は一覧 GET→dedup→write を直列化し二重 POST を防ぐ" "$result"

if [[ -f "$(lock_path Owner Repo github.com)" ]]; then result=0; else result=1; fi
record_result "post lock key は可読 prefix と完全 SHA-256 を持つ" "$result"

write_request "$TEST_ROOT/result-collision-one.json" "$TEST_ROOT/request-collision-one.json" magi a-b c github.com
write_request "$TEST_ROOT/result-collision-two.json" "$TEST_ROOT/request-collision-two.json" magi a b-c github.com
write_request "$TEST_ROOT/result-other-host.json" "$TEST_ROOT/request-other-host.json" magi a-b c git.example.com
for request in request-collision-one request-collision-two request-other-host; do
  env "${COMMON_ENV[@]}" PUBLISHER_ID="$request" bash "$POST_SCRIPT" "$TEST_ROOT/$request.json" \
    >"$TEST_ROOT/$request.out" 2>"$TEST_ROOT/$request.err"
done
if [[ "$(lock_path a-b c github.com)" != "$(lock_path a b-c github.com)" \
  && "$(lock_path a-b c github.com)" != "$(lock_path a-b c git.example.com)" \
  && -f "$(lock_path a-b c github.com)" && -f "$(lock_path a b-c github.com)" \
  && -f "$(lock_path a-b c git.example.com)" ]]; then result=0; else result=1; fi
record_result "owner/repo 境界と forge host が異なる lock key は衝突しない" "$result"

: >"$TEST_ROOT/events.log"
rm -f -- "$TEST_ROOT/comments.json"
write_request "$TEST_ROOT/result-default.json" "$TEST_ROOT/request-default.json"
if env PATH="$TEST_ROOT/bin:$PATH" GH_EVENT_LOG="$TEST_ROOT/events.log" GH_STATE="$TEST_ROOT/comments.json" \
  EXECUTION_BUDGET_JSON="$TEST_ROOT/budget.json" XDG_RUNTIME_DIR="$TEST_ROOT/default-runtime" \
  PUBLISHER_ID=default bash "$POST_SCRIPT" "$TEST_ROOT/request-default.json" \
  >"$TEST_ROOT/default.out" 2>"$TEST_ROOT/default.err" \
  && [[ ! -e "$TEST_ROOT/default-runtime/claude-review-post-owner-repo-7.lock" ]]; then result=0; else result=1; fi
record_result "REVIEW_POST_USE_LOCK 未設定では lock を取得せず従来動作する" "$result"

: >"$TEST_ROOT/events.log"
rm -f -- "$TEST_ROOT/comments.json"
write_request "$TEST_ROOT/result-blocked.json" "$TEST_ROOT/request-blocked.json"
write_request "$TEST_ROOT/result-blocked.json" "$TEST_ROOT/request-blocked.json" codex
exec 7>"$(lock_path Owner Repo github.com)"
flock 7
set +e
env PATH="$TEST_ROOT/bin:$PATH" GH_EVENT_LOG="$TEST_ROOT/events.log" GH_STATE="$TEST_ROOT/comments.json" \
  EXECUTION_BUDGET_JSON="$TEST_ROOT/short-budget.json" XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
  REVIEW_POST_USE_LOCK=1 PUBLISHER_ID=blocked bash "$POST_SCRIPT" "$TEST_ROOT/request-blocked.json" \
  >"$TEST_ROOT/blocked.out" 2>"$TEST_ROOT/blocked.err"
STATUS=$?
set -e
exec 7>&-
if [[ "$STATUS" -eq 1 && ! -s "$TEST_ROOT/events.log" ]] \
  && jq -e '.github_writes == []' "$TEST_ROOT/result-blocked.json" >/dev/null; then result=0; else result=1; fi
record_result "post lock 取得失敗は GitHub API/record_write 前に exit 1 へ合流する" "$result"
if [[ "$STATUS" -eq 1 ]] && grep -Fq '1秒以内' "$TEST_ROOT/blocked.err"; then result=0; else result=1; fi
record_result "post lock budget は request の codex backend から選択する" "$result"

if grep -Fq 'step 2' "$POST_REF" && grep -Fq 'step 6' "$POST_REF" \
  && grep -Fq 'step 1/3/4/5' "$POST_REF" && grep -Fq 'PR-3' "$POST_REF"; then result=0; else result=1; fi
record_result "PR-2 と PR-3 の fencing 責務境界を明記する" "$result"

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
[[ "$FAIL" -eq 0 ]]
