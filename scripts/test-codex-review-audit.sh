#!/usr/bin/env bash
# scripts/test-codex-review-audit.sh — codex-review-merge.sh の契約テスト
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
  local findings_json="$2"
  local audit_json="$3"
  local self_tamper_json="$4"
  local failed_personas_json="$5"
  local case_dir="$TEST_ROOT/$name"
  mkdir -p "$case_dir"
  printf '%s\n' "$findings_json" >"$case_dir/findings.json"
  printf '%s\n' "$audit_json" >"$case_dir/audit.json"
  printf '%s\n' "$self_tamper_json" >"$case_dir/self-tamper.json"
  printf '%s\n' "$failed_personas_json" >"$case_dir/failed-personas.json"
  CASE_RESULT="$case_dir/result.json"
  CASE_EXIT=0
  if bash "$SCRIPT" \
    "$case_dir/findings.json" \
    "$case_dir/audit.json" \
    "$case_dir/self-tamper.json" \
    "$case_dir/failed-personas.json" \
    >"$CASE_RESULT" 2>"$case_dir/stderr"; then
    CASE_EXIT=0
  else
    CASE_EXIT=$?
  fi
}

findings_basic='[
  {"id":"F-001","source_persona":"METATRON","path":"src/a.sh","line":10,"headline":"危険な入力","body":"metatron body","gate":"block"},
  {"id":"F-002","source_persona":"LELIEL","path":"src/b.sh","line":20,"headline":"影響範囲","body":"leliel body","gate":"defer"},
  {"id":"F-003","source_persona":"CASPER","path":"src/c.sh","line":30,"headline":"規約違反","body":"casper body","gate":"manual"}
]'
audit_basic='[
  {"group_id":"G-001","member_ids":["F-001","F-002"],"canonical_persona":"METATRON"},
  {"group_id":"G-002","member_ids":["F-003"],"canonical_persona":"MELCHIOR"}
]'

# 1. 全件成功、完全カバレッジ、CASPER canonical の強制と gate 優先順位。
run_case success "$findings_basic" "$audit_basic" false '[]'
if [[ "$CASE_EXIT" -eq 0 ]] && jq -e '
  .pipeline_status == "complete"
  and .failed_personas == []
  and (.manual_review | length) == 0
  and (.findings | length) == 2
  and .findings[0].group_id == "G-001"
  and .findings[0].canonical_persona == "METATRON"
  and .findings[0].source_personas == ["METATRON", "LELIEL"]
  and .findings[0].gate == "block"
  and .findings[0].path == "src/a.sh"
  and .findings[1].canonical_persona == "CASPER"
  and .findings[1].source_personas == ["CASPER"]
  and .findings[1].gate == "manual"
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "全件成功時に canonical/source_personas/gate を決定的に復元する" "$result"

# 2. failed_personas はそのまま保持し、データ欠損として incomplete にする。
run_case failed-persona "$findings_basic" "$audit_basic" false '["LELIEL","SANDALPHON"]'
if [[ "$CASE_EXIT" -eq 0 ]] && jq -e '
  .pipeline_status == "incomplete"
  and .failed_personas == ["LELIEL", "SANDALPHON"]
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "failed_personas が非空なら pipeline_status=incomplete で入力配列を保持する" "$result"

# 2b. path/headline/body の空文字列は入力契約違反。
run_case empty-finding-fields '[
  {"id":"F-001","source_persona":"METATRON","path":"","line":1,"headline":"","body":"","gate":"block"}
]' '[]' false '[]'
if [[ "$CASE_EXIT" -eq 2 ]]; then
  result=0
else
  result=1
fi
record_result "path/headline/body の空文字列を入力契約違反にする" "$result"

# 3. 不正 JSONと非配列は監査全体失敗。
run_case audit-parse-error "$findings_basic" '{not valid json' false '[]'
if [[ "$CASE_EXIT" -eq 1 ]] && jq -e '
  .pipeline_status == "incomplete" and (.findings | length) == 0
  and (.manual_review | length) == 3
  and all(.manual_review[]; .gate == "manual")
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "監査出力のパース不能を全件 raw/manual に戻す" "$result"

run_case audit-not-array "$findings_basic" '{"group_id":"G-001"}' false '[]'
if [[ "$CASE_EXIT" -eq 1 ]] && jq -e '(.manual_review | length) == 3 and .pipeline_status == "incomplete"' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "監査出力が配列でない場合を監査全体失敗にする" "$result"

# 4. 監査全体で member ID が重複。
run_case duplicate-member '[
  {"id":"F-001","source_persona":"METATRON","path":"a","line":1,"headline":"a","body":"a","gate":"defer"},
  {"id":"F-002","source_persona":"LELIEL","path":"b","line":2,"headline":"b","body":"b","gate":"defer"}
]' '[
  {"group_id":"G-001","member_ids":["F-001"],"canonical_persona":"METATRON"},
  {"group_id":"G-002","member_ids":["F-001","F-002"],"canonical_persona":"LELIEL"}
]' false '[]'
if [[ "$CASE_EXIT" -eq 1 ]] && jq -e '(.manual_review | length) == 2 and (.findings | length) == 0' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "member_id の重複を監査全体失敗にする" "$result"

# 5. 入力 ID の欠落。
run_case missing-member '[
  {"id":"F-001","source_persona":"METATRON","path":"a","line":1,"headline":"a","body":"a","gate":"defer"},
  {"id":"F-002","source_persona":"LELIEL","path":"b","line":2,"headline":"b","body":"b","gate":"defer"}
]' '[{"group_id":"G-001","member_ids":["F-001"],"canonical_persona":"METATRON"}]' false '[]'
if [[ "$CASE_EXIT" -eq 1 ]] && jq -e '(.manual_review | length) == 2 and .pipeline_status == "incomplete"' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "member_id の欠落を監査全体失敗にする" "$result"

# 6. 未知 ID。
run_case unknown-member '[
  {"id":"F-001","source_persona":"METATRON","path":"a","line":1,"headline":"a","body":"a","gate":"defer"}
]' '[{"group_id":"G-001","member_ids":["F-001","F-999"],"canonical_persona":"METATRON"}]' false '[]'
if [[ "$CASE_EXIT" -eq 1 ]] && jq -e '(.manual_review | length) == 1 and (.findings | length) == 0' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "未知 member_id の混入を監査全体失敗にする" "$result"

# 7. group 内の gate は block > manual > defer。
run_case gate-priority '[
  {"id":"F-001","source_persona":"METATRON","path":"a","line":1,"headline":"a","body":"a","gate":"block"},
  {"id":"F-002","source_persona":"METATRON","path":"b","line":2,"headline":"b","body":"b","gate":"defer"}
]' '[{"group_id":"G-001","member_ids":["F-001","F-002"],"canonical_persona":"METATRON"}]' false '[]'
if [[ "$CASE_EXIT" -eq 0 ]] && jq -e '.pipeline_status == "complete" and .findings[0].gate == "block"' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "group 内で割れた gate を block に解決する" "$result"

# 8. CASPER と非 CASPER の混在は当該 group だけ拒否。
run_case casper-boundary '[
  {"id":"F-001","source_persona":"METATRON","path":"a","line":1,"headline":"a","body":"a","gate":"block"},
  {"id":"F-002","source_persona":"CASPER","path":"b","line":2,"headline":"b","body":"b","gate":"defer"},
  {"id":"F-003","source_persona":"BALTHASAR","path":"c","line":3,"headline":"c","body":"c","gate":"manual"}
]' '[
  {"group_id":"G-BAD","member_ids":["F-001","F-002"],"canonical_persona":"CASPER"},
  {"group_id":"G-GOOD","member_ids":["F-003"],"canonical_persona":"BALTHASAR"}
]' false '[]'
if [[ "$CASE_EXIT" -eq 0 ]] && jq -e '
  .pipeline_status == "complete"
  and (.findings | length) == 1
  and .findings[0].group_id == "G-GOOD"
  and (.manual_review | length) == 2
  and ([.manual_review[].id] | sort) == ["F-001", "F-002"]
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "CASPER 境界違反を group 単位で退避し他 group を採用する" "$result"

# 8b. canonical_persona が妥当な非CASPER値でも、CASPER/非CASPER混在自体を理由に拒否する。
run_case casper-boundary-valid-canonical '[
  {"id":"F-001","source_persona":"METATRON","path":"a","line":1,"headline":"a","body":"a","gate":"block"},
  {"id":"F-002","source_persona":"CASPER","path":"b","line":2,"headline":"b","body":"b","gate":"defer"},
  {"id":"F-003","source_persona":"BALTHASAR","path":"c","line":3,"headline":"c","body":"c","gate":"manual"}
]' '[
  {"group_id":"G-BAD","member_ids":["F-001","F-002"],"canonical_persona":"METATRON"},
  {"group_id":"G-GOOD","member_ids":["F-003"],"canonical_persona":"BALTHASAR"}
]' false '[]'
if [[ "$CASE_EXIT" -eq 0 ]] && jq -e '
  .pipeline_status == "complete"
  and (.findings | length) == 1
  and .findings[0].group_id == "G-GOOD"
  and (.manual_review | length) == 2
  and ([.manual_review[].id] | sort) == ["F-001", "F-002"]
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "canonical が妥当な非CASPER値でもCASPER混在groupは拒否する" "$result"

# 9. group_id 重複と空 member_ids は当該 group だけ拒否。
run_case duplicate-group-id '[
  {"id":"F-001","source_persona":"METATRON","path":"a","line":1,"headline":"a","body":"a","gate":"defer"},
  {"id":"F-002","source_persona":"LELIEL","path":"b","line":2,"headline":"b","body":"b","gate":"defer"},
  {"id":"F-003","source_persona":"BALTHASAR","path":"c","line":3,"headline":"c","body":"c","gate":"block"}
]' '[
  {"group_id":"G-DUP","member_ids":["F-001"],"canonical_persona":"METATRON"},
  {"group_id":"G-DUP","member_ids":["F-002"],"canonical_persona":"LELIEL"},
  {"group_id":"G-OK","member_ids":["F-003"],"canonical_persona":"BALTHASAR"}
]' false '[]'
if [[ "$CASE_EXIT" -eq 0 ]] && jq -e '
  (.findings | length) == 1 and .findings[0].group_id == "G-OK"
  and ([.manual_review[].id] | sort) == ["F-001", "F-002"]
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "重複 group_id を当該 group のみ manual に退避する" "$result"

run_case empty-member-group '[
  {"id":"F-001","source_persona":"METATRON","path":"a","line":1,"headline":"a","body":"a","gate":"defer"}
]' '[
  {"group_id":"G-EMPTY","member_ids":[],"canonical_persona":"METATRON"},
  {"group_id":"G-OK","member_ids":["F-001"],"canonical_persona":"METATRON"}
]' false '[]'
if [[ "$CASE_EXIT" -eq 0 ]] && jq -e '
  (.findings | length) == 1 and .findings[0].group_id == "G-OK"
  and (.manual_review | length) == 0
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "空 member_ids の group を拒否し有効 group を採用する" "$result"

# 10. canonical は非 CASPER allowlist 内なら source に含まれなくても許可。
run_case reattribution '[
  {"id":"F-001","source_persona":"METATRON","path":"a","line":1,"headline":"a","body":"a","gate":"defer"},
  {"id":"F-002","source_persona":"LELIEL","path":"b","line":2,"headline":"b","body":"b","gate":"manual"}
]' '[{"group_id":"G-001","member_ids":["F-001","F-002"],"canonical_persona":"BALTHASAR"}]' false '[]'
if [[ "$CASE_EXIT" -eq 0 ]] && jq -e '
  .pipeline_status == "complete"
  and .findings[0].canonical_persona == "BALTHASAR"
  and .findings[0].source_personas == ["METATRON", "LELIEL"]
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "allowlist 内の意図的な canonical 再帰属を受理する" "$result"

# 11. findings が空でも self-tamper 合成 finding は manual_review に追加し、status は complete。
run_case self-tamper '[]' '[]' true '[]'
if [[ "$CASE_EXIT" -eq 0 ]] && jq -e '
  .pipeline_status == "complete"
  and .findings == []
  and (.manual_review | length) == 1
  and .manual_review[0].id == "F-SELF-001"
  and .manual_review[0].gate == "manual"
  and .manual_review[0].canonical_persona == null
  and .manual_review[0].source_personas == []
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "self-tamper 合成 finding を追加しても pipeline_status=complete を維持する" "$result"

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
