#!/usr/bin/env bash
# scripts/test-review-adjudicate-findings.sh — review adjudication の契約テスト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/review-adjudicate-findings.sh"
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
  local engine="$2"
  local findings_file="$3"
  local validity_file="$4"
  local importance_file="$5"
  CASE_RESULT="$TEST_ROOT/$name-result.json"
  CASE_EXIT=0
  if bash "$SCRIPT" "$engine" "$findings_file" "$validity_file" "$importance_file" \
    >"$CASE_RESULT" 2>"$TEST_ROOT/$name.stderr"; then
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

# 1. final_gate 導出表
GATE_META="$TEST_ROOT/gate-meta.json"
cat >"$GATE_META" <<'JSON'
[
  {"id":"F-001","source_persona":"METATRON","reported_gate":"block"},
  {"id":"F-002","source_persona":"METATRON","reported_gate":"defer"},
  {"id":"F-003","source_persona":"METATRON","reported_gate":"manual"},
  {"id":"F-004","source_persona":"METATRON","reported_gate":null},
  {"id":"F-005","source_persona":"METATRON","reported_gate":"block"}
]
JSON
GATE_VALIDITY="$TEST_ROOT/gate-validity.json"
cat >"$GATE_VALIDITY" <<'JSON'
[
  {"id":"F-001","verdict":"valid","reason":"確認済み"},
  {"id":"F-002","verdict":"valid","reason":"確認済み"},
  {"id":"F-003","verdict":"valid","reason":"確認済み"},
  {"id":"F-004","verdict":"valid","reason":"確認済み"},
  {"id":"F-005","verdict":"false_positive","reason":"誤検知"}
]
JSON
GATE_IMPORTANCE="$TEST_ROOT/gate-importance.json"
cat >"$GATE_IMPORTANCE" <<'JSON'
[
  {"id":"F-001","importance":"HIGH","reason":"影響大"},
  {"id":"F-002","importance":"MEDIUM","reason":"影響中"},
  {"id":"F-003","importance":"LOW","reason":"影響小"}
]
JSON
run_case gate-table codex "$GATE_META" "$GATE_VALIDITY" "$GATE_IMPORTANCE"
expect_json "HIGH は block になる" '.results[0].importance == "HIGH" and .results[0].importance_status == "ok" and .results[0].final_gate == "block"'
expect_json "MEDIUM は block になる" '.results[1].importance == "MEDIUM" and .results[1].importance_status == "ok" and .results[1].final_gate == "block"'
expect_json "LOW は defer になる" '.results[2].importance == "LOW" and .results[2].importance_status == "ok" and .results[2].final_gate == "defer"'
expect_json "重要度欠落は failed と defer になる" '.results[3].importance == null and .results[3].importance_status == "failed" and .results[3].final_gate == "defer"'
expect_json "false_positive は重要度を見ず defer になる" '.results[4].verdict == "false_positive" and .results[4].importance == null and .results[4].importance_status == "not_applicable" and .results[4].final_gate == "defer"'

# 2. CASPER の特別扱いを Codex engine に限定する
CASPER_META="$TEST_ROOT/casper-meta.json"
cat >"$CASPER_META" <<'JSON'
[{"id":"F-101","source_persona":"CASPER","reported_gate":"block"}]
JSON
CASPER_VALIDITY="$TEST_ROOT/casper-validity.json"
cat >"$CASPER_VALIDITY" <<'JSON'
[{"id":"F-101","verdict":"valid","reason":"確認済み"}]
JSON
CASPER_IMPORTANCE="$TEST_ROOT/casper-importance.json"
cat >"$CASPER_IMPORTANCE" <<'JSON'
[{"id":"F-101","importance":"LOW","reason":"影響小"}]
JSON
run_case casper-codex codex "$CASPER_META" "$CASPER_VALIDITY" "$CASPER_IMPORTANCE"
expect_json "Codex の CASPER は重要度を見ず deterministic に block になる" '.results[0].final_gate == "block" and .results[0].importance == null and .results[0].importance_status == "not_applicable"'
run_case casper-magi magi "$CASPER_META" "$CASPER_VALIDITY" "$CASPER_IMPORTANCE"
expect_json "MAGI の CASPER は通常どおり LOW を defer にする" '.results[0].importance == "LOW" and .results[0].importance_status == "ok" and .results[0].final_gate == "defer"'

# 3. 妥当性全体失敗は CASPER を含め全件 null にする
GLOBAL_META="$TEST_ROOT/global-meta.json"
cat >"$GLOBAL_META" <<'JSON'
[
  {"id":"F-201","source_persona":"METATRON","reported_gate":"defer"},
  {"id":"F-202","source_persona":"CASPER","reported_gate":"block"}
]
JSON
GLOBAL_VALIDITY="$TEST_ROOT/global-validity.json"
cat >"$GLOBAL_VALIDITY" <<'JSON'
{"error":"AUDIT_ERROR"}
JSON
GLOBAL_IMPORTANCE="$TEST_ROOT/global-importance.json"
cat >"$GLOBAL_IMPORTANCE" <<'JSON'
[]
JSON
run_case validity-global-failure codex "$GLOBAL_META" "$GLOBAL_VALIDITY" "$GLOBAL_IMPORTANCE"
expect_exit "妥当性全体失敗は exit 1 になる" 1
expect_json_any_exit "妥当性全体失敗では CASPER を含む全件の verdict と final_gate が null になる" '.validity_global_failure == true and all(.results[]; .verdict == null and .final_gate == null and .importance == null and .importance_status == "not_applicable")'

# 4. 妥当性結果の ID 集合不一致はデータ層の exit 1 になる
MISMATCH_META="$TEST_ROOT/mismatch-meta.json"
cat >"$MISMATCH_META" <<'JSON'
[
  {"id":"F-301","source_persona":"METATRON","reported_gate":null},
  {"id":"F-302","source_persona":"METATRON","reported_gate":null}
]
JSON
MISMATCH_IMPORTANCE="$TEST_ROOT/mismatch-importance.json"
cat >"$MISMATCH_IMPORTANCE" <<'JSON'
[]
JSON
MISSING_VALIDITY="$TEST_ROOT/missing-validity.json"
cat >"$MISSING_VALIDITY" <<'JSON'
[{"id":"F-301","verdict":"valid","reason":"確認済み"}]
JSON
EXTRA_VALIDITY="$TEST_ROOT/extra-validity.json"
cat >"$EXTRA_VALIDITY" <<'JSON'
[
  {"id":"F-301","verdict":"valid","reason":"確認済み"},
  {"id":"F-302","verdict":"valid","reason":"確認済み"},
  {"id":"F-999","verdict":"valid","reason":"余分"}
]
JSON
DUPLICATE_VALIDITY="$TEST_ROOT/duplicate-validity.json"
cat >"$DUPLICATE_VALIDITY" <<'JSON'
[
  {"id":"F-301","verdict":"valid","reason":"確認済み"},
  {"id":"F-301","verdict":"needs_human","reason":"重複"},
  {"id":"F-302","verdict":"valid","reason":"確認済み"}
]
JSON
run_case validity-missing-id codex "$MISMATCH_META" "$MISSING_VALIDITY" "$MISMATCH_IMPORTANCE"
expect_exit "妥当性結果の ID 欠落は exit 1 になる" 1
expect_json_any_exit "妥当性結果の ID 欠落は global_failure になる" '.validity_global_failure == true'
run_case validity-extra-id codex "$MISMATCH_META" "$EXTRA_VALIDITY" "$MISMATCH_IMPORTANCE"
expect_exit "妥当性結果の余分な ID は exit 1 になる" 1
expect_json_any_exit "妥当性結果の余分な ID は global_failure になる" '.validity_global_failure == true'
run_case validity-duplicate-id codex "$MISMATCH_META" "$DUPLICATE_VALIDITY" "$MISMATCH_IMPORTANCE"
expect_exit "妥当性結果の重複 ID は exit 1 になる" 1
expect_json_any_exit "妥当性結果の重複 ID は global_failure になる" '.validity_global_failure == true'

# 5. findings meta の入力契約違反は exit 2 になる
CONTRACT_VALIDITY="$TEST_ROOT/contract-validity.json"
cat >"$CONTRACT_VALIDITY" <<'JSON'
[{"id":"F-401","verdict":"valid","reason":"確認済み"}]
JSON
CONTRACT_IMPORTANCE="$TEST_ROOT/contract-importance.json"
cat >"$CONTRACT_IMPORTANCE" <<'JSON'
[]
JSON
META_DUPLICATE="$TEST_ROOT/meta-duplicate.json"
cat >"$META_DUPLICATE" <<'JSON'
[
  {"id":"F-401","source_persona":"METATRON","reported_gate":null},
  {"id":"F-401","source_persona":"BALTHASAR","reported_gate":null}
]
JSON
META_MISSING_GATE="$TEST_ROOT/meta-missing-gate.json"
cat >"$META_MISSING_GATE" <<'JSON'
[{"id":"F-401","source_persona":"METATRON"}]
JSON
META_BAD_GATE="$TEST_ROOT/meta-bad-gate.json"
cat >"$META_BAD_GATE" <<'JSON'
[{"id":"F-401","source_persona":"METATRON","reported_gate":"unknown"}]
JSON
META_NOT_ARRAY="$TEST_ROOT/meta-not-array.json"
cat >"$META_NOT_ARRAY" <<'JSON'
{"id":"F-401","source_persona":"METATRON","reported_gate":null}
JSON
META_EMPTY_PERSONA="$TEST_ROOT/meta-empty-persona.json"
cat >"$META_EMPTY_PERSONA" <<'JSON'
[{"id":"F-401","source_persona":"","reported_gate":null}]
JSON
run_case contract-duplicate codex "$META_DUPLICATE" "$CONTRACT_VALIDITY" "$CONTRACT_IMPORTANCE"
expect_exit "findings meta の重複 ID は exit 2 になる" 2
run_case contract-missing-gate codex "$META_MISSING_GATE" "$CONTRACT_VALIDITY" "$CONTRACT_IMPORTANCE"
expect_exit "reported_gate 欠落は exit 2 になる" 2
run_case contract-bad-gate codex "$META_BAD_GATE" "$CONTRACT_VALIDITY" "$CONTRACT_IMPORTANCE"
expect_exit "reported_gate の不正値は exit 2 になる" 2
run_case contract-not-array codex "$META_NOT_ARRAY" "$CONTRACT_VALIDITY" "$CONTRACT_IMPORTANCE"
expect_exit "findings meta の非配列は exit 2 になる" 2
run_case contract-empty-persona codex "$META_EMPTY_PERSONA" "$CONTRACT_VALIDITY" "$CONTRACT_IMPORTANCE"
expect_exit "source_persona の空文字列は exit 2 になる" 2

# 6. MAGI の reported_gate は null のまま通過させる
PASS_THROUGH_META="$TEST_ROOT/pass-through-meta.json"
cat >"$PASS_THROUGH_META" <<'JSON'
[
  {"id":"F-601","source_persona":"METATRON","reported_gate":null},
  {"id":"F-602","source_persona":"BALTHASAR","reported_gate":null}
]
JSON
PASS_THROUGH_VALIDITY="$TEST_ROOT/pass-through-validity.json"
cat >"$PASS_THROUGH_VALIDITY" <<'JSON'
[
  {"id":"F-601","verdict":"valid","reason":"確認済み"},
  {"id":"F-602","verdict":"valid","reason":"確認済み"}
]
JSON
PASS_THROUGH_IMPORTANCE="$TEST_ROOT/pass-through-importance.json"
cat >"$PASS_THROUGH_IMPORTANCE" <<'JSON'
[
  {"id":"F-601","importance":"HIGH","reason":"影響大"},
  {"id":"F-602","importance":"LOW","reason":"影響小"}
]
JSON
run_case reported-gate-pass-through magi "$PASS_THROUGH_META" "$PASS_THROUGH_VALIDITY" "$PASS_THROUGH_IMPORTANCE"
expect_json "MAGI の reported_gate は全件 null のままになる" 'all(.results[]; .reported_gate == null)'

# 7. 空の findings meta は他ファイルを読まず成功する
EMPTY_META="$TEST_ROOT/empty-meta.json"
cat >"$EMPTY_META" <<'JSON'
[]
JSON
run_case empty-findings codex "$EMPTY_META" "$TEST_ROOT/not-present-validity.json" "$TEST_ROOT/not-present-importance.json"
expect_exit "空の findings meta は exit 0 になる" 0
expect_json "空の findings meta は空結果かつ global_failure false になる" '.results == [] and .validity_global_failure == false'

# 8. needs_human は valid と同じ重要度 lookup 経路を通る
NEEDS_HUMAN_META="$TEST_ROOT/needs-human-meta.json"
cat >"$NEEDS_HUMAN_META" <<'JSON'
[
  {"id":"F-801","source_persona":"METATRON","reported_gate":"defer"},
  {"id":"F-802","source_persona":"METATRON","reported_gate":"block"}
]
JSON
NEEDS_HUMAN_VALIDITY="$TEST_ROOT/needs-human-validity.json"
cat >"$NEEDS_HUMAN_VALIDITY" <<'JSON'
[
  {"id":"F-801","verdict":"needs_human","reason":"追加確認が必要"},
  {"id":"F-802","verdict":"needs_human","reason":"追加確認が必要"}
]
JSON
NEEDS_HUMAN_IMPORTANCE="$TEST_ROOT/needs-human-importance.json"
cat >"$NEEDS_HUMAN_IMPORTANCE" <<'JSON'
[
  {"id":"F-801","importance":"HIGH","reason":"影響大"},
  {"id":"F-802","importance":"LOW","reason":"影響小"}
]
JSON
run_case needs-human codex "$NEEDS_HUMAN_META" "$NEEDS_HUMAN_VALIDITY" "$NEEDS_HUMAN_IMPORTANCE"
expect_json "needs_human と HIGH は block になる" '.results[0].verdict == "needs_human" and .results[0].importance_status == "ok" and .results[0].final_gate == "block"'
expect_json "needs_human と LOW は defer になる" '.results[1].verdict == "needs_human" and .results[1].importance_status == "ok" and .results[1].final_gate == "defer"'

# 追加確認: 重要度の malformed 出力は per-finding failure に留まる
IMPORTANCE_FAILURE_META="$TEST_ROOT/importance-failure-meta.json"
cat >"$IMPORTANCE_FAILURE_META" <<'JSON'
[{"id":"F-901","source_persona":"METATRON","reported_gate":null}]
JSON
IMPORTANCE_FAILURE_VALIDITY="$TEST_ROOT/importance-failure-validity.json"
cat >"$IMPORTANCE_FAILURE_VALIDITY" <<'JSON'
[{"id":"F-901","verdict":"valid","reason":"確認済み"}]
JSON
IMPORTANCE_FAILURE_FILE="$TEST_ROOT/importance-failure.json"
cat >"$IMPORTANCE_FAILURE_FILE" <<'JSON'
{"unexpected":"shape"}
JSON
run_case importance-failure codex "$IMPORTANCE_FAILURE_META" "$IMPORTANCE_FAILURE_VALIDITY" "$IMPORTANCE_FAILURE_FILE"
expect_json "重要度 malformed は exit 0 の per-finding failure になる" '.validity_global_failure == false and .results[0].importance == null and .results[0].importance_status == "failed" and .results[0].final_gate == "defer"'

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
