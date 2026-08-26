#!/usr/bin/env bash
# scripts/test-codex-review-merge.sh — codex-review-merge の契約テスト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/codex-review-merge.sh"
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

run_case() {
  local name="$1"
  shift
  CASE_RESULT="$TEST_ROOT/$name-result.json"
  CASE_STDERR="$TEST_ROOT/$name.stderr"
  CASE_EXIT=0
  if bash "$SCRIPT" "$@" >"$CASE_RESULT" 2>"$CASE_STDERR"; then
    CASE_EXIT=0
  else
    CASE_EXIT=$?
  fi
}

expect_json() {
  local description="$1"
  local filter="$2"
  local status=1
  if [[ "$CASE_EXIT" -eq 0 ]] && jq -e "$filter" "$CASE_RESULT" >/dev/null 2>&1; then
    status=0
  fi
  record_result "$description" "$status"
}

expect_json_any_exit() {
  local description="$1"
  local filter="$2"
  local status=1
  if jq -e "$filter" "$CASE_RESULT" >/dev/null 2>&1; then
    status=0
  fi
  record_result "$description" "$status"
}

expect_exit() {
  local description="$1"
  local expected="$2"
  local status=1
  [[ "$CASE_EXIT" -eq "$expected" ]] && status=0
  record_result "$description" "$status"
}

expect_stderr() {
  local description="$1"
  local expected="$2"
  local status=1
  if grep -Fq "$expected" "$CASE_STDERR"; then
    status=0
  fi
  record_result "$description" "$status"
}

SELF_FALSE="$TEST_ROOT/self-false.json"
cat >"$SELF_FALSE" <<'JSON'
false
JSON
FAILED_EMPTY="$TEST_ROOT/failed-empty.json"
cat >"$FAILED_EMPTY" <<'JSON'
[]
JSON

# 1. valid + block は grouped finding の final_gate にだけ反映する。
CASE_1_FINDINGS="$TEST_ROOT/case-1-findings.json"
cat >"$CASE_1_FINDINGS" <<'JSON'
[
  {"id":"F-001","source_persona":"METATRON","path":"src/a.sh","line":10,"headline":"block finding","body":"body","gate":"block"}
]
JSON
CASE_1_AUDIT="$TEST_ROOT/case-1-audit.json"
cat >"$CASE_1_AUDIT" <<'JSON'
[
  {"group_id":"G-001","canonical_persona":"METATRON","member_ids":["F-001"]}
]
JSON
CASE_1_ADJUDICATION="$TEST_ROOT/case-1-adjudication.json"
cat >"$CASE_1_ADJUDICATION" <<'JSON'
{
  "artifact_type":"review-adjudication",
  "schema_version":"1",
  "validity_global_failure":false,
  "results":[
    {"id":"F-001","verdict":"valid","importance":"HIGH","importance_status":"ok","reported_gate":"block","final_gate":"block"}
  ]
}
JSON
run_case hard-valid-block --mode hard "$CASE_1_FINDINGS" "$CASE_1_AUDIT" "$SELF_FALSE" "$FAILED_EMPTY" "$CASE_1_ADJUDICATION"
expect_json "valid + block は final_gate のみに反映される" \
  '(.findings | length == 1) and .findings[0].final_gate == "block" and (.findings[0] | has("gate") | not) and (.findings[0] | has("reported_gate") | not)'

# 2. false_positive + defer は defer としてマージする。
CASE_2_FINDINGS="$TEST_ROOT/case-2-findings.json"
cat >"$CASE_2_FINDINGS" <<'JSON'
[
  {"id":"F-002","source_persona":"METATRON","path":"src/b.sh","line":20,"headline":"false positive","body":"body","gate":"block"}
]
JSON
CASE_2_AUDIT="$TEST_ROOT/case-2-audit.json"
cat >"$CASE_2_AUDIT" <<'JSON'
[
  {"group_id":"G-002","canonical_persona":"METATRON","member_ids":["F-002"]}
]
JSON
CASE_2_ADJUDICATION="$TEST_ROOT/case-2-adjudication.json"
cat >"$CASE_2_ADJUDICATION" <<'JSON'
{
  "artifact_type":"review-adjudication",
  "schema_version":"1",
  "validity_global_failure":false,
  "results":[
    {"id":"F-002","verdict":"false_positive","importance":null,"importance_status":"not_applicable","reported_gate":"block","final_gate":"defer"}
  ]
}
JSON
run_case hard-false-positive-defer --mode hard "$CASE_2_FINDINGS" "$CASE_2_AUDIT" "$SELF_FALSE" "$FAILED_EMPTY" "$CASE_2_ADJUDICATION"
expect_json "false_positive + defer は defer にマージされる" '.findings[0].final_gate == "defer"'

# 3. 異なる final_gate の同一 group は block を優先する。
CASE_3_FINDINGS="$TEST_ROOT/case-3-findings.json"
cat >"$CASE_3_FINDINGS" <<'JSON'
[
  {"id":"F-003","source_persona":"METATRON","path":"src/c.sh","line":30,"headline":"block member","body":"body","gate":"defer"},
  {"id":"F-004","source_persona":"BALTHASAR","path":"src/c.sh","line":31,"headline":"defer member","body":"body","gate":"block"}
]
JSON
CASE_3_AUDIT="$TEST_ROOT/case-3-audit.json"
cat >"$CASE_3_AUDIT" <<'JSON'
[
  {"group_id":"G-003","canonical_persona":"METATRON","member_ids":["F-003","F-004"]}
]
JSON
CASE_3_ADJUDICATION="$TEST_ROOT/case-3-adjudication.json"
cat >"$CASE_3_ADJUDICATION" <<'JSON'
{
  "artifact_type":"review-adjudication",
  "schema_version":"1",
  "validity_global_failure":false,
  "results":[
    {"id":"F-003","verdict":"valid","importance":"HIGH","importance_status":"ok","reported_gate":"defer","final_gate":"block"},
    {"id":"F-004","verdict":"valid","importance":"LOW","importance_status":"ok","reported_gate":"block","final_gate":"defer"}
  ]
}
JSON
run_case hard-strongest-final-gate --mode hard "$CASE_3_FINDINGS" "$CASE_3_AUDIT" "$SELF_FALSE" "$FAILED_EMPTY" "$CASE_3_ADJUDICATION"
expect_json "同一 group の block は defer より強くマージされる" '.findings | length == 1 and .[0].final_gate == "block"'

# 4. failed_personas が空で global failure がなければ complete になる。
CASE_4_FINDINGS="$TEST_ROOT/case-4-findings.json"
cat >"$CASE_4_FINDINGS" <<'JSON'
[
  {"id":"F-005","source_persona":"SANDALPHON","path":"src/d.sh","line":40,"headline":"complete finding","body":"body","gate":"defer"}
]
JSON
CASE_4_AUDIT="$TEST_ROOT/case-4-audit.json"
cat >"$CASE_4_AUDIT" <<'JSON'
[
  {"group_id":"G-004","canonical_persona":"SANDALPHON","member_ids":["F-005"]}
]
JSON
CASE_4_ADJUDICATION="$TEST_ROOT/case-4-adjudication.json"
cat >"$CASE_4_ADJUDICATION" <<'JSON'
{
  "artifact_type":"review-adjudication",
  "schema_version":"1",
  "validity_global_failure":false,
  "results":[
    {"id":"F-005","verdict":"needs_human","importance":"LOW","importance_status":"ok","reported_gate":"defer","final_gate":"defer"}
  ]
}
JSON
run_case hard-complete --mode hard "$CASE_4_FINDINGS" "$CASE_4_AUDIT" "$SELF_FALSE" "$FAILED_EMPTY" "$CASE_4_ADJUDICATION"
expect_json "failed_personas 空かつ global failure なしは complete になる" '.pipeline_status == "complete"'

# 5. global failure でない結果の verdict null は不正として exit 2 にする。
CASE_5_FINDINGS="$TEST_ROOT/case-5-findings.json"
cat >"$CASE_5_FINDINGS" <<'JSON'
[
  {"id":"F-006","source_persona":"METATRON","path":"src/e.sh","line":50,"headline":"null verdict","body":"body","gate":"block"}
]
JSON
CASE_5_AUDIT="$TEST_ROOT/case-5-audit.json"
cat >"$CASE_5_AUDIT" <<'JSON'
[
  {"group_id":"G-005","canonical_persona":"METATRON","member_ids":["F-006"]}
]
JSON
CASE_5_BAD_ADJUDICATION="$TEST_ROOT/case-5-bad-adjudication.json"
cat >"$CASE_5_BAD_ADJUDICATION" <<'JSON'
{
  "artifact_type":"review-adjudication",
  "schema_version":"1",
  "validity_global_failure":false,
  "results":[
    {"id":"F-006","verdict":null,"importance":null,"importance_status":"not_applicable","reported_gate":"block","final_gate":"block"}
  ]
}
JSON
run_case hard-null-verdict --mode hard "$CASE_5_FINDINGS" "$CASE_5_AUDIT" "$SELF_FALSE" "$FAILED_EMPTY" "$CASE_5_BAD_ADJUDICATION"
expect_exit "validity_global_failure false の verdict null は exit 2 になる" 2

# 6. false_positive + block は契約違反として exit 2 にする。
CASE_6_FINDINGS="$TEST_ROOT/case-6-findings.json"
cat >"$CASE_6_FINDINGS" <<'JSON'
[
  {"id":"F-007","source_persona":"METATRON","path":"src/f.sh","line":60,"headline":"contradictory gate","body":"body","gate":"block"}
]
JSON
CASE_6_AUDIT="$TEST_ROOT/case-6-audit.json"
cat >"$CASE_6_AUDIT" <<'JSON'
[
  {"group_id":"G-006","canonical_persona":"METATRON","member_ids":["F-007"]}
]
JSON
CASE_6_BAD_ADJUDICATION="$TEST_ROOT/case-6-bad-adjudication.json"
cat >"$CASE_6_BAD_ADJUDICATION" <<'JSON'
{
  "artifact_type":"review-adjudication",
  "schema_version":"1",
  "validity_global_failure":false,
  "results":[
    {"id":"F-007","verdict":"false_positive","importance":null,"importance_status":"not_applicable","reported_gate":"block","final_gate":"block"}
  ]
}
JSON
run_case hard-false-positive-block --mode hard "$CASE_6_FINDINGS" "$CASE_6_AUDIT" "$SELF_FALSE" "$FAILED_EMPTY" "$CASE_6_BAD_ADJUDICATION"
expect_exit "false_positive + block は exit 2 になる" 2

# 7. 5/6 の悪い field を直すと、隣接する正当なデータは通過する。
CASE_5_GOOD_ADJUDICATION="$TEST_ROOT/case-5-good-adjudication.json"
cat >"$CASE_5_GOOD_ADJUDICATION" <<'JSON'
{
  "artifact_type":"review-adjudication",
  "schema_version":"1",
  "validity_global_failure":false,
  "results":[
    {"id":"F-006","verdict":"valid","importance":null,"importance_status":"not_applicable","reported_gate":"block","final_gate":"block"}
  ]
}
JSON
run_case hard-null-verdict-corrected --mode hard "$CASE_5_FINDINGS" "$CASE_5_AUDIT" "$SELF_FALSE" "$FAILED_EMPTY" "$CASE_5_GOOD_ADJUDICATION"
expect_exit "verdict null を valid に直すと exit 0 になる" 0

CASE_6_GOOD_ADJUDICATION="$TEST_ROOT/case-6-good-adjudication.json"
cat >"$CASE_6_GOOD_ADJUDICATION" <<'JSON'
{
  "artifact_type":"review-adjudication",
  "schema_version":"1",
  "validity_global_failure":false,
  "results":[
    {"id":"F-007","verdict":"false_positive","importance":null,"importance_status":"not_applicable","reported_gate":"block","final_gate":"defer"}
  ]
}
JSON
run_case hard-false-positive-block-corrected --mode hard "$CASE_6_FINDINGS" "$CASE_6_AUDIT" "$SELF_FALSE" "$FAILED_EMPTY" "$CASE_6_GOOD_ADJUDICATION"
expect_exit "false_positive の final_gate を defer に直すと exit 0 になる" 0

# 8. validity_global_failure は全件を raw manual_review に退避する。
CASE_8_FINDINGS="$TEST_ROOT/case-8-findings.json"
cat >"$CASE_8_FINDINGS" <<'JSON'
[
  {"id":"F-008","source_persona":"LELIEL","path":"src/g.sh","line":70,"headline":"global failure finding","body":"raw body","gate":"block"}
]
JSON
CASE_8_AUDIT="$TEST_ROOT/case-8-audit.json"
cat >"$CASE_8_AUDIT" <<'JSON'
[
  {"group_id":"G-008","canonical_persona":"LELIEL","member_ids":["F-008"]}
]
JSON
CASE_8_ADJUDICATION="$TEST_ROOT/case-8-adjudication.json"
cat >"$CASE_8_ADJUDICATION" <<'JSON'
{
  "artifact_type":"review-adjudication",
  "schema_version":"1",
  "validity_global_failure":true,
  "results":[
    {"id":"F-008","verdict":null,"importance":null,"importance_status":"not_applicable","reported_gate":null,"final_gate":null}
  ]
}
JSON
run_case hard-validity-global-failure --mode hard "$CASE_8_FINDINGS" "$CASE_8_AUDIT" "$SELF_FALSE" "$FAILED_EMPTY" "$CASE_8_ADJUDICATION"
expect_exit "validity_global_failure true は exit 1 になる" 1
expect_json_any_exit "global failure は findings を空にし raw findings を manual_review に入れる" \
  '.validity_global_failure == true and .findings == [] and (.manual_review | length == 1) and .manual_review[0].id == "F-008" and .manual_review[0].body == "raw body"'

# 9. adjudication artifact の不存在は hard mode の入力エラーにする。
CASE_9_FINDINGS="$TEST_ROOT/case-9-findings.json"
cat >"$CASE_9_FINDINGS" <<'JSON'
[
  {"id":"F-009","source_persona":"METATRON","path":"src/i.sh","line":90,"headline":"missing artifact","body":"body","gate":"defer"}
]
JSON
CASE_9_AUDIT="$TEST_ROOT/case-9-audit.json"
cat >"$CASE_9_AUDIT" <<'JSON'
[
  {"group_id":"G-009","canonical_persona":"METATRON","member_ids":["F-009"]}
]
JSON
CASE_9_MISSING_ADJUDICATION="$TEST_ROOT/case-9-missing-adjudication.json"
run_case hard-missing-adjudication --mode hard "$CASE_9_FINDINGS" "$CASE_9_AUDIT" "$SELF_FALSE" "$FAILED_EMPTY" "$CASE_9_MISSING_ADJUDICATION"
expect_exit "存在しない adjudication artifact は exit 2 になる" 2

# 10. adjudication results と findings の ID 集合不一致は入力エラーにする。
CASE_10_FINDINGS="$TEST_ROOT/case-10-findings.json"
cat >"$CASE_10_FINDINGS" <<'JSON'
[
  {"id":"F-010","source_persona":"METATRON","path":"src/j.sh","line":100,"headline":"mismatched id","body":"body","gate":"defer"}
]
JSON
CASE_10_AUDIT="$TEST_ROOT/case-10-audit.json"
cat >"$CASE_10_AUDIT" <<'JSON'
[
  {"group_id":"G-010","canonical_persona":"METATRON","member_ids":["F-010"]}
]
JSON
CASE_10_ADJUDICATION="$TEST_ROOT/case-10-adjudication.json"
cat >"$CASE_10_ADJUDICATION" <<'JSON'
{
  "artifact_type":"review-adjudication",
  "schema_version":"1",
  "validity_global_failure":false,
  "results":[
    {"id":"F-010-OTHER","verdict":"valid","importance":"LOW","importance_status":"ok","reported_gate":"defer","final_gate":"defer"}
  ]
}
JSON
run_case hard-adjudication-id-mismatch --mode hard "$CASE_10_FINDINGS" "$CASE_10_AUDIT" "$SELF_FALSE" "$FAILED_EMPTY" "$CASE_10_ADJUDICATION"
expect_exit "adjudication results と findings の ID 集合不一致は exit 2 になる" 2

# 11. fast mode は self-reported gate を従来どおり gate に出す。
CASE_11_FINDINGS="$TEST_ROOT/case-11-findings.json"
cat >"$CASE_11_FINDINGS" <<'JSON'
[
  {"id":"F-011","source_persona":"METATRON","path":"src/k.sh","line":110,"headline":"fast block","body":"body","gate":"block"}
]
JSON
CASE_11_AUDIT="$TEST_ROOT/case-11-audit.json"
cat >"$CASE_11_AUDIT" <<'JSON'
[
  {"group_id":"G-011","canonical_persona":"METATRON","member_ids":["F-011"]}
]
JSON
run_case fast-self-reported-block --mode fast "$CASE_11_FINDINGS" "$CASE_11_AUDIT" "$SELF_FALSE" "$FAILED_EMPTY"
expect_json "fast mode は self-reported gate を gate として出力する" '.findings[0].gate == "block" and (.findings[0] | has("final_gate") | not)'

# 12. fast mode は adjudication の5番目の引数なしで成功する。
CASE_12_FINDINGS="$TEST_ROOT/case-12-findings.json"
cat >"$CASE_12_FINDINGS" <<'JSON'
[
  {"id":"F-012","source_persona":"BALTHASAR","path":"src/l.sh","line":120,"headline":"fast four args","body":"body","gate":"defer"}
]
JSON
CASE_12_AUDIT="$TEST_ROOT/case-12-audit.json"
cat >"$CASE_12_AUDIT" <<'JSON'
[
  {"group_id":"G-012","canonical_persona":"BALTHASAR","member_ids":["F-012"]}
]
JSON
run_case fast-four-args --mode fast "$CASE_12_FINDINGS" "$CASE_12_AUDIT" "$SELF_FALSE" "$FAILED_EMPTY"
expect_exit "fast mode は4つの positional args だけで exit 0 になる" 0

# 13. mode なし／不正 mode は usage と exit 2 になる。
run_case usage-no-mode
expect_exit "mode なしで引数もない呼び出しは exit 2 になる" 2
expect_stderr "mode なしの呼び出しは usage を stderr に出す" "usage:"

run_case usage-invalid-mode --mode invalid
expect_exit "不正な mode は exit 2 になる" 2
expect_stderr "不正な mode は usage を stderr に出す" "usage:"

# 14. hard mode は adjudication artifact を省略できない。
CASE_14_FINDINGS="$TEST_ROOT/case-14-findings.json"
cat >"$CASE_14_FINDINGS" <<'JSON'
[
  {"id":"F-014","source_persona":"METATRON","path":"src/n.sh","line":140,"headline":"missing fifth arg","body":"body","gate":"defer"}
]
JSON
CASE_14_AUDIT="$TEST_ROOT/case-14-audit.json"
cat >"$CASE_14_AUDIT" <<'JSON'
[
  {"group_id":"G-014","canonical_persona":"METATRON","member_ids":["F-014"]}
]
JSON
run_case hard-missing-fifth-arg --mode hard "$CASE_14_FINDINGS" "$CASE_14_AUDIT" "$SELF_FALSE" "$FAILED_EMPTY"
expect_exit "hard mode の adjudication artifact 省略は exit 2 になる" 2

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
