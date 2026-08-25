#!/usr/bin/env bash
# scripts/test-review-dedup-findings.sh — 共通 findings dedup の契約テスト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/review-dedup-findings.sh"
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
  local keys="$2"
  local input_file="$3"
  CASE_RESULT="$TEST_ROOT/$name-result.json"
  CASE_EXIT=0
  if bash "$SCRIPT" "$keys" "$input_file" >"$CASE_RESULT" 2>"$TEST_ROOT/$name.stderr"; then
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

expect_exit() {
  local description="$1"
  local expected="$2"
  local status=1
  [[ "$CASE_EXIT" -eq "$expected" ]] && status=0
  record_result "$description" "$status"
}

MAGI_INPUT="$TEST_ROOT/magi.json"
cat >"$MAGI_INPUT" <<'JSON'
[
  {"persona":"MELCHIOR","headline":"first","original_path":"a.sh","original_line":10,"evidence":null,"body":"same body","id":"M-001","note":"first occurrence"},
  {"persona":"BALTHASAR","headline":"first","original_path":"a.sh","original_line":10,"evidence":null,"body":"same body","id":"M-002","note":"other persona"},
  {"persona":"MELCHIOR","headline":"first","original_path":"a.sh","original_line":10,"evidence":"","body":"same body","id":"M-003","note":"empty evidence"},
  {"persona":"MELCHIOR","headline":"first","original_path":"a.sh","original_line":10,"evidence":null,"body":"same body","id":"M-004","note":"duplicate"},
  {"persona":"BALTHASAR","headline":"first","original_path":"a.sh","original_line":10,"evidence":null,"body":"same body","id":"M-005","note":"duplicate"},
  {"persona":"MELCHIOR","headline":"last","original_path":"b.sh","original_line":20,"evidence":"run","body":"last body","id":"M-006","note":"last occurrence"}
]
JSON

run_case magi 'persona,headline,original_path,original_line,evidence,body' "$MAGI_INPUT"
expect_json "MAGI形状をdedupし、first-occurrence orderとpersona境界を保持する" \
  'length == 4 and [.[].id] == ["M-001", "M-002", "M-003", "M-006"]'
expect_json "MAGIの非キー属性を代表候補からlosslessに保持する" \
  '.[0].note == "first occurrence" and .[1].note == "other persona"'
expect_json "evidence nullと空文字列を別値として扱う" \
  '([.[].evidence | type] | sort) == ["null", "null", "string", "string"] and .[0].evidence == null and .[2].evidence == ""'
expect_json "gateなしのMAGI形状にgateを追加しない" \
  'all(.[]; has("gate") | not)'

CODEX_INPUT="$TEST_ROOT/codex.json"
cat >"$CODEX_INPUT" <<'JSON'
[
  {"path":"a.sh","line":3,"headline":"same","body":"body","gate":"defer","id":"C-001","note":"first"},
  {"path":"a.sh","line":3,"headline":"same","body":"body","gate":"block","id":"C-002","note":"strongest"},
  {"path":"a.sh","line":3,"headline":"same","body":"body","gate":"manual","id":"C-003","note":"middle"},
  {"path":"b.sh","line":8,"headline":"next","body":"next body","gate":"manual","id":"C-004","note":"next"},
  {"path":"c.sh","line":13,"headline":"manual wins","body":"manual body","gate":"defer","id":"C-005","note":"defer"},
  {"path":"c.sh","line":13,"headline":"manual wins","body":"manual body","gate":"manual","id":"C-006","note":"manual"}
]
JSON

run_case codex 'headline,path,line,body' "$CODEX_INPUT"
expect_json "Codex通常形状をdedupし、first-occurrence orderを保持する" \
  'length == 3 and [.[].id] == ["C-001", "C-004", "C-005"]'
expect_json "重複gateはblockを最強値として代表候補へ集約する" \
  '.[0].gate == "block" and .[0].note == "first" and .[1].gate == "manual" and .[2].gate == "manual"'

CASPER_INPUT="$TEST_ROOT/casper.json"
cat >"$CASPER_INPUT" <<'JSON'
[
  {"persona":"CASPER","path":"a.sh","line":4,"headline":"same","body":"body","evidence":"e","id":"S-001","note":"first"},
  {"persona":"CASPER","path":"a.sh","line":4,"headline":"same","body":"body","evidence":"e","id":"S-002","note":"duplicate"},
  {"persona":"METATRON","path":"a.sh","line":4,"headline":"same","body":"body","evidence":"e","id":"S-003","note":"other persona"}
]
JSON

run_case casper 'persona,headline,path,line,evidence,body' "$CASPER_INPUT"
expect_json "Codex CASPER形状を指定キーでdedupする" \
  'length == 2 and [.[].id] == ["S-001", "S-003"]'
expect_json "CASPER形状でもpersonaをまたいだ統合をしない" \
  '.[0].persona == "CASPER" and .[1].persona == "METATRON"'
expect_json "CASPER形状の非キー属性を保持する" \
  '.[0].note == "first" and .[1].note == "other persona"'

MISSING_INPUT="$TEST_ROOT/missing-key.json"
cat >"$MISSING_INPUT" <<'JSON'
[
  {"headline":"valid","path":"a.sh","line":1,"body":"body"},
  {"headline":"missing","path":"a.sh","line":2}
]
JSON
run_case missing 'headline,path,line,body' "$MISSING_INPUT"
expect_exit "指定キー欠落は入力契約違反としてexit 2にする" 2

NULL_INPUT="$TEST_ROOT/null-value.json"
cat >"$NULL_INPUT" <<'JSON'
[{"headline":"null","path":"a.sh","line":1,"body":"body","evidence":null}]
JSON
run_case null-value 'headline,path,line,body,evidence' "$NULL_INPUT"
expect_json "指定キーが存在して値がnullなら正常に処理する" \
  'length == 1 and (.[0] | has("evidence")) and .[0].evidence == null'

NON_ARRAY_INPUT="$TEST_ROOT/non-array.json"
cat >"$NON_ARRAY_INPUT" <<'JSON'
{"headline":"not array"}
JSON
run_case non-array 'headline' "$NON_ARRAY_INPUT"
expect_exit "入力がJSON配列でない場合はexit 2にする" 2

LARGE_BODY_FILE="$TEST_ROOT/large-body.txt"
head -c 3000000 /dev/zero | tr '\0' 'x' >"$LARGE_BODY_FILE"
LARGE_INPUT="$TEST_ROOT/large-body.json"
jq -n --rawfile body "$LARGE_BODY_FILE" '[{
  headline: "large",
  path: "large.sh",
  line: 1,
  body: $body,
  gate: "defer"
}]' >"$LARGE_INPUT"
run_case large-body 'headline,path,line,body' "$LARGE_INPUT"
expect_json "大きなbodyをARG_MAXに依存せず処理する" \
  '(length == 1) and ((.[0].body | length) == 3000000)'

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
