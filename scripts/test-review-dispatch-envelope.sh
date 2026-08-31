#!/usr/bin/env bash
# scripts/test-review-dispatch-envelope.sh — review dispatch envelope の契約テスト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/review-dispatch-envelope.sh"
PASS=0
FAIL=0
TEST_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

record_result() {
  local description="$1"
  local status="$2"
  if [[ "$status" -eq 0 ]]; then
    echo "PASS: $description"
    ((PASS++)) || true
  else
    echo "FAIL: $description"
    ((FAIL++)) || true
  fi
}

write_envelope() {
  local output="$1"
  shift
  local review_kind="$1"
  shift
  local backend="$1"
  shift
  local dispatch_status="$1"
  shift
  local gate_decision="$1"
  shift
  local lgtm_eligible="$1"
  shift
  local blocking_count="$1"
  shift
  local manual_review_required="$1"
  shift
  local post_state="$1"
  shift
  local artifact_ref="$1"
  shift
  local adjudication_ref="$1"
  shift
  local failure_reason="$1"
  shift
  local manual_review="${1:-null}"
  jq -n \
    --arg review_kind "$review_kind" \
    --arg backend "$backend" \
    --arg dispatch_status "$dispatch_status" \
    --arg gate_decision "$gate_decision" \
    --argjson lgtm_eligible "$lgtm_eligible" \
    --argjson blocking_count "$blocking_count" \
    --argjson manual_review_required "$manual_review_required" \
    --arg post_state "$post_state" \
    --arg artifact_ref "$artifact_ref" \
    --arg adjudication_ref "$adjudication_ref" \
    --arg failure_reason "$failure_reason" \
    --argjson manual_review "$manual_review" \
    '{
      schema_version:"1",
      artifact_type:"review-dispatch-result",
      review_kind:$review_kind,
      backend:$backend,
      dispatch_status:$dispatch_status,
      gate_decision:$gate_decision,
      lgtm_eligible:$lgtm_eligible,
      blocking_count:$blocking_count,
      manual_review_required:$manual_review_required,
      manual_review:$manual_review,
      artifact_ref:(if $artifact_ref == "" then null else $artifact_ref end),
      adjudication_ref:(if $adjudication_ref == "" then null else $adjudication_ref end),
      post_state:$post_state,
      failure_reason:(if $failure_reason == "" then null else $failure_reason end),
      native_result:{test:true}
    }' >"$output"
}

run_validator() {
  local envelope="$1"
  if bash "$SCRIPT" validate "$envelope" >"$TEST_ROOT/stdout" 2>"$TEST_ROOT/stderr"; then
    VALIDATOR_EXIT=0
  else
    VALIDATOR_EXIT=$?
  fi
}

expect_exit() {
  local description="$1"
  local expected="$2"
  local envelope="$3"
  run_validator "$envelope"
  if [[ "$VALIDATOR_EXIT" -eq "$expected" ]]; then
    result=0
  else
    result=1
  fi
  record_result "$description" "$result"
}

CASE_FILE="$TEST_ROOT/envelope.json"

# 1. fast/magi、fast/codex、hard/magi、hard/codex の正常 envelope。
write_envelope "$CASE_FILE" fast magi complete lgtm true 0 false not_applicable "" "" ""
expect_exit "正常な fast/magi envelope を受理する" 0 "$CASE_FILE"
write_envelope "$CASE_FILE" fast codex complete lgtm true 0 false not_applicable "" "" ""
expect_exit "正常な fast/codex envelope を受理する" 0 "$CASE_FILE"
write_envelope "$CASE_FILE" hard magi complete block false 2 false posted "/tmp/findings.json" "/tmp/adjudication.json" ""
expect_exit "正常な hard/magi envelope を受理する" 0 "$CASE_FILE"
write_envelope "$CASE_FILE" hard codex complete lgtm true 0 false posted "/tmp/findings.json" "/tmp/adjudication.json" ""
expect_exit "正常な hard/codex envelope を受理する" 0 "$CASE_FILE"

# 2. lgtm_eligible の固定述語違反。
write_envelope "$CASE_FILE" fast magi incomplete lgtm true 0 false not_applicable "" "" "engine incomplete"
expect_exit "incomplete なのに lgtm_eligible=true を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" fast magi complete lgtm true 3 false not_applicable "" "" ""
expect_exit "blocking_count=3 なのに lgtm_eligible=true を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" fast magi complete lgtm true 0 true not_applicable "" "" ""
expect_exit "manual_review_required=true なのに lgtm_eligible=true を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" hard magi complete lgtm true 0 false post_failed "/tmp/findings.json" "/tmp/adjudication.json" ""
expect_exit "hard の post_failed で lgtm_eligible=true を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" fast magi complete indeterminate true 0 false not_applicable "" "" ""
expect_exit "indeterminate なのに lgtm_eligible=true を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" fast magi failed indeterminate false null true not_applicable "" "" ""
expect_exit "failed なのに failure_reason=null を拒否する" 2 "$CASE_FILE"

# 2. downstream の状態整合性を fail-closed に固定する。
write_envelope "$CASE_FILE" fast magi incomplete indeterminate false null true not_applicable "" "" "engine incomplete"
jq '.failure_reason = ""' "$CASE_FILE" >"$TEST_ROOT/empty-failure.json"
expect_exit "incomplete なのに failure_reason=空文字列を拒否する" 2 "$TEST_ROOT/empty-failure.json"
write_envelope "$CASE_FILE" hard magi failed block false null true post_failed "/tmp/findings.json" "/tmp/adjudication.json" "dispatch failed"
expect_exit "failed なのに gate_decision=block を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" hard magi failed indeterminate false null true posted "/tmp/findings.json" "" "dispatch failed"
expect_exit "hard・投稿成功後に dispatch=failed へ落ちた posted 状態を受理する" 0 "$CASE_FILE"
write_envelope "$CASE_FILE" fast magi complete indeterminate false 0 false not_applicable "" "" ""
expect_exit "indeterminate なのに dispatch_status=complete を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" hard magi complete block false 2 false post_failed "/tmp/findings.json" "/tmp/adjudication.json" ""
expect_exit "post_state=post_failed なのに failure_reason=null を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" hard magi unavailable indeterminate false null true post_failed "" "" "engine 起動不能"
expect_exit "hard の unavailable で post_state=post_failed を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" hard magi unavailable indeterminate false null true not_applicable "" "" "engine 起動不能"
expect_exit "hard の unavailable で post_state=not_applicable を受理する" 0 "$CASE_FILE"
write_envelope "$CASE_FILE" hard magi complete manual false 0 true posted "/tmp/findings.json" "/tmp/adjudication.json" "" '{"ids":["F-1"]}'
expect_exit "hard の gate_decision=manual を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" hard codex complete lgtm false 0 false posted "/tmp/findings.json" "" ""
expect_exit "hard の lgtm で adjudication_ref=null を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" hard magi complete block false null false posted "/tmp/findings.json" "/tmp/adjudication.json" ""
expect_exit "gate=block で blocking_count=null を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" hard magi complete block false 0 false posted "/tmp/findings.json" "/tmp/adjudication.json" ""
expect_exit "gate=block で blocking_count=0 を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" fast magi complete lgtm false 2 false not_applicable "" "" ""
expect_exit "gate=lgtm で blocking_count=2 を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" fast magi complete block false 1 false not_applicable "" "" "" '{"ids":["F-1"]}'
expect_exit "manual_review 非null なのに manual_review_required=false を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" fast codex unavailable indeterminate false null true not_applicable "" "" "Codex companion unavailable"
expect_exit "manual_review_required=true / manual_review=null（逆方向は課さない）を受理する" 0 "$CASE_FILE"

# 3. fail-closed の incomplete/unavailable と hard の投稿失敗・degraded。
write_envelope "$CASE_FILE" fast magi incomplete indeterminate false null true not_applicable "" "" "CASPER 単体失敗"
expect_exit "incomplete で null count・manual 必須・非 LGTM を受理する" 0 "$CASE_FILE"
write_envelope "$CASE_FILE" fast codex unavailable indeterminate false null true not_applicable "" "" "Codex companion unavailable"
expect_exit "unavailable で null count・manual 必須を受理する" 0 "$CASE_FILE"
write_envelope "$CASE_FILE" hard magi complete block false 2 false post_failed "/tmp/findings.json" "/tmp/adjudication.json" "GitHub API 投稿失敗"
expect_exit "hard の投稿失敗でも gate 判定を保持して受理する" 0 "$CASE_FILE"
write_envelope "$CASE_FILE" hard magi incomplete indeterminate false null true posted "" "" "structure 層の失敗"
expect_exit "hard の structure degraded 経路を受理する" 0 "$CASE_FILE"
write_envelope "$CASE_FILE" hard codex complete lgtm true 0 false posted "/tmp/findings.json" "/tmp/adjudication.json" ""
expect_exit "hard の clean LGTM を受理する" 0 "$CASE_FILE"
write_envelope "$CASE_FILE" hard codex complete lgtm false 0 true posted "/tmp/findings.json" "/tmp/adjudication.json" "" '{"finding_ids":["F-123"]}'
expect_exit "hard の needs_human 由来 manual_review_required=true を受理する" 0 "$CASE_FILE"

# 4. fast/hard 固有の状態、count の型、必須キーを検証する。
write_envelope "$CASE_FILE" fast magi complete lgtm true 0 false not_applicable "/tmp/findings.json" "" ""
expect_exit "fast の artifact_ref 非 null を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" hard magi complete block false 1 false not_applicable "/tmp/findings.json" "/tmp/adjudication.json" ""
expect_exit "hard の post_state=not_applicable を拒否する" 2 "$CASE_FILE"
write_envelope "$CASE_FILE" fast magi complete block false 0 false not_applicable "" "" ""
jq '.blocking_count = "0"' "$CASE_FILE" >"$TEST_ROOT/string-count.json"
expect_exit "blocking_count の文字列を拒否する" 2 "$TEST_ROOT/string-count.json"
write_envelope "$CASE_FILE" fast magi complete block false -1 false not_applicable "" "" ""
expect_exit "blocking_count の負数を拒否する" 2 "$CASE_FILE"
jq 'del(.native_result)' "$CASE_FILE" >"$TEST_ROOT/missing-key.json"
expect_exit "必須キーの欠落を拒否する" 2 "$TEST_ROOT/missing-key.json"

# 5. null count を受理しつつ、0 への丸めを許さない。
write_envelope "$CASE_FILE" fast magi incomplete indeterminate false null true not_applicable "" "" "count unavailable"
run_validator "$CASE_FILE"
if [[ "$VALIDATOR_EXIT" -eq 0 ]] && jq -e '.blocking_count == null and (.blocking_count | type) == "null"' "$CASE_FILE" >/dev/null 2>&1; then
  result=0
else
  result=1
fi
record_result "blocking_count=null を null のまま受理する" "$result"
write_envelope "$CASE_FILE" fast magi complete lgtm true null false not_applicable "" "" ""
expect_exit "blocking_count=null を 0 とみなして LGTM にする envelope を拒否する" 2 "$CASE_FILE"

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
