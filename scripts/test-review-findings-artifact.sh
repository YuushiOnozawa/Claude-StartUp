#!/usr/bin/env bash
# scripts/test-review-findings-artifact.sh — canonical findings artifact の契約テスト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/review-findings-artifact.sh"
FIXTURE_DIR="$SCRIPT_DIR/tests/fixtures"
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

run_transform() {
  local name="$1"
  local engine="$2"
  local input_file="$3"
  local failed_file="${4:-}"
  local case_dir="$TEST_ROOT/$name"
  mkdir -p "$case_dir"
  CASE_RESULT="$case_dir/result.json"
  CASE_EXIT=0
  if [[ -n "$failed_file" ]]; then
    if bash "$SCRIPT" "$engine" "$input_file" "$failed_file" >"$CASE_RESULT" 2>"$case_dir/stderr"; then
      CASE_EXIT=0
    else
      CASE_EXIT=$?
    fi
  else
    if bash "$SCRIPT" "$engine" "$input_file" >"$CASE_RESULT" 2>"$case_dir/stderr"; then
      CASE_EXIT=0
    else
      CASE_EXIT=$?
    fi
  fi
}

validate_artifact() {
  if jq -e '
    def nonempty_string: type == "string" and length > 0;
    def gates: ["block", "defer", "manual"];
    def provenances: ["model_reported", "deterministic"];
    def personas: ["MELCHIOR", "BALTHASAR", "METATRON", "SANDALPHON", "LELIEL", "CASPER"];
    def valid_line:
      type == "null"
      or (type == "number" and floor == . and . > 0);
    def valid_evidence:
      type == "null" or nonempty_string;
    type == "object"
    and has("schema_version") and .schema_version == "1"
    and has("engine") and (.engine | IN("magi", "codex"))
    and has("detection_status") and (.detection_status | IN("complete", "incomplete", "unknown"))
    and has("failed_personas")
    and (
      if .failed_personas == null then true
      else
        (.failed_personas | type) == "array"
        and all(.failed_personas[];
          . as $persona
          | type == "string" and length > 0 and (personas | index($persona)) != null
        )
        and ((.failed_personas | length) == (.failed_personas | unique | length))
      end
    )
    and (
      (.detection_status == "complete" and .failed_personas == [])
      or (.detection_status == "incomplete" and (.failed_personas | type) == "array" and (.failed_personas | length) > 0)
      or (.detection_status == "unknown" and .failed_personas == null)
    )
    and has("findings") and (.findings | type) == "array"
    and ([.findings[].id] | length) == ([.findings[].id] | unique | length)
    and all(.findings[];
      . as $finding
      | all(["id", "source_persona", "path", "line", "headline", "body", "evidence", "reported_gate", "gate_provenance"][];
          . as $key | ($finding | has($key)))
      and ($finding.id | nonempty_string)
      and ($finding.source_persona as $persona | (personas | index($persona)) != null)
      and ($finding.path | nonempty_string)
      and ($finding.line | valid_line)
      and ($finding.headline | nonempty_string)
      and ($finding.body | nonempty_string)
      and ($finding.evidence | valid_evidence)
      and (($finding.reported_gate == null) or ($finding.reported_gate as $gate | (gates | index($gate)) != null))
      and (($finding.gate_provenance == null) or ($finding.gate_provenance as $provenance | (provenances | index($provenance)) != null))
      and (($finding.reported_gate == null) == ($finding.gate_provenance == null))
    )
    and (
      if .engine == "magi" then
        all(.findings[]; .reported_gate == null and .gate_provenance == null)
      else
        all(.findings[];
          if .source_persona == "CASPER" then
            .reported_gate == "block" and .gate_provenance == "deterministic"
          else
            (.reported_gate as $gate | (gates | index($gate)) != null)
            and .gate_provenance == "model_reported"
          end
        )
      end
    )
  ' "$1" >/dev/null 2>&1; then
    return 0
  fi
  return 2
}

MAGI_FIXTURE="$FIXTURE_DIR/findings-artifact-magi-table.json"
CODEX_FIXTURE="$FIXTURE_DIR/findings-artifact-codex-table.json"

# 1. MAGI fixture は canonical schema を満たし、gate 軸を持たない。
run_transform magi-valid magi "$MAGI_FIXTURE"
if [[ "$CASE_EXIT" -eq 0 ]] && validate_artifact "$CASE_RESULT" && jq -e '
  all(.findings[]; .reported_gate == null and .gate_provenance == null)
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "MAGI fixture が schema validator を通り gate 軸が全件 null になる" "$result"

# 2. Codex fixture は CASPER だけ deterministic、他5体は model_reported。
run_transform codex-valid codex "$CODEX_FIXTURE"
if [[ "$CASE_EXIT" -eq 0 ]] && validate_artifact "$CASE_RESULT" && jq -e '
  ([.findings[] | select(.source_persona == "CASPER") | .gate_provenance] | unique) == ["deterministic"]
  and ([.findings[] | select(.source_persona != "CASPER") | .gate_provenance] | unique) == ["model_reported"]
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "Codex fixture が schema validator を通り provenance を復元する" "$result"

# 3. reported_gate はペルソナの自己申告であり、最終 gate フィールドではない。
if jq -e '
  ([.findings[] | select(.reported_gate == "block")] | length) > 0
  and (has("final_gate") | not)
  and ([.findings[] | (has("gate") or has("final_gate"))] | any | not)
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "reported_gate を最終 gate として保存しない" "$result"

# 4. failed-personas を省略すると detection_status は unknown/null になる。
if [[ "$CASE_EXIT" -eq 0 ]] && jq -e '
  .detection_status == "unknown" and .failed_personas == null
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "failed-personas 省略時に unknown/null を保持する" "$result"

FAILED_NONEMPTY="$TEST_ROOT/failed-personas.json"
FAILED_EMPTY="$TEST_ROOT/failed-personas-empty.json"
jq -n '["CASPER"]' >"$FAILED_NONEMPTY"
jq -n '[]' >"$FAILED_EMPTY"

# 5. failed-personas の内容と status の対応。
run_transform codex-incomplete codex "$CODEX_FIXTURE" "$FAILED_NONEMPTY"
if [[ "$CASE_EXIT" -eq 0 ]] && jq -e '
  .detection_status == "incomplete" and .failed_personas == ["CASPER"]
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "failed-personas 非空時に incomplete と入力配列を保持する" "$result"

run_transform codex-complete codex "$CODEX_FIXTURE" "$FAILED_EMPTY"
if [[ "$CASE_EXIT" -eq 0 ]] && jq -e '
  .detection_status == "complete" and .failed_personas == []
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "failed-personas 空配列時に complete を保持する" "$result"

# 6. canonical artifact の組合せ規則違反はすべて validator の exit 2 になる。
MUTATION_SOURCE="$TEST_ROOT/codex-incomplete/result.json"
BAD_STATUS="$TEST_ROOT/bad-status.json"
BAD_MAGI_GATE="$TEST_ROOT/bad-magi-gate.json"
BAD_CASPER_PROVENANCE="$TEST_ROOT/bad-casper-provenance.json"
BAD_CODEX_PROVENANCE="$TEST_ROOT/bad-codex-provenance.json"
BAD_HALF_NULL="$TEST_ROOT/bad-half-null.json"
jq '.detection_status = "complete"' "$MUTATION_SOURCE" >"$BAD_STATUS"
jq '.findings[0].reported_gate = "block"' "$MUTATION_SOURCE" >"$BAD_MAGI_GATE"
jq '(.findings[] | select(.source_persona == "CASPER")).gate_provenance = "model_reported"' "$MUTATION_SOURCE" >"$BAD_CASPER_PROVENANCE"
jq '(.findings[] | select(.source_persona == "MELCHIOR")).gate_provenance = "deterministic"' "$MUTATION_SOURCE" >"$BAD_CODEX_PROVENANCE"
jq '.findings[0].gate_provenance = "model_reported"' "$TEST_ROOT/magi-valid/result.json" >"$BAD_HALF_NULL"

bad_combo_status=0
for bad_file in "$BAD_STATUS" "$BAD_CASPER_PROVENANCE" "$BAD_CODEX_PROVENANCE" "$BAD_HALF_NULL"; do
  if validate_artifact "$bad_file"; then
    bad_combo_status=1
  else
    bad_exit=$?
    [[ "$bad_exit" -eq 2 ]] || bad_combo_status=1
  fi
done
run_transform magi-for-gate-violation magi "$MAGI_FIXTURE"
if jq '.findings[0].reported_gate = "block"' "$CASE_RESULT" >"$BAD_MAGI_GATE" && validate_artifact "$BAD_MAGI_GATE"; then
  bad_combo_status=1
else
  bad_exit=$?
  [[ "$bad_exit" -eq 2 ]] || bad_combo_status=1
fi
record_result "status/gate の組合せ規則違反をすべて exit 2 にする" "$bad_combo_status"

FAILED_UNKNOWN="$TEST_ROOT/failed-personas-unknown.json"
FAILED_DUPLICATE="$TEST_ROOT/failed-personas-duplicate.json"
jq -n '["UNKNOWN"]' >"$FAILED_UNKNOWN"
jq -n '["CASPER", "CASPER"]' >"$FAILED_DUPLICATE"
run_transform failed-unknown-persona codex "$CODEX_FIXTURE" "$FAILED_UNKNOWN"
unknown_persona_status=0
[[ "$CASE_EXIT" -eq 2 ]] || unknown_persona_status=1
run_transform failed-duplicate-persona codex "$CODEX_FIXTURE" "$FAILED_DUPLICATE"
[[ "$CASE_EXIT" -eq 2 ]] || unknown_persona_status=1
record_result "許可外ペルソナ名と failed-personas 重複を exit 2 にする" "$unknown_persona_status"

# 7. 入力契約違反は全て exit 2。
BAD_MISSING="$TEST_ROOT/bad-missing.json"
BAD_LINE_STRING="$TEST_ROOT/bad-line-string.json"
BAD_LINE_ZERO="$TEST_ROOT/bad-line-zero.json"
BAD_EVIDENCE_EMPTY="$TEST_ROOT/bad-evidence-empty.json"
jq 'del(.findings[0].body)' "$MAGI_FIXTURE" >"$BAD_MISSING"
jq '.findings[0].original_line = "17"' "$MAGI_FIXTURE" >"$BAD_LINE_STRING"
jq '.findings[0].original_line = 0' "$MAGI_FIXTURE" >"$BAD_LINE_ZERO"
jq '.findings[0].evidence = ""' "$MAGI_FIXTURE" >"$BAD_EVIDENCE_EMPTY"
broken_input_status=0
for bad_input in "$BAD_MISSING" "$BAD_LINE_STRING" "$BAD_LINE_ZERO" "$BAD_EVIDENCE_EMPTY"; do
  run_transform "broken-$(basename "$bad_input" .json)" magi "$bad_input"
  [[ "$CASE_EXIT" -eq 2 ]] || broken_input_status=1
done
run_transform unknown-engine invalid "$MAGI_FIXTURE"
[[ "$CASE_EXIT" -eq 2 ]] || broken_input_status=1
record_result "キー欠落・型不正・line 0・空 evidence・未知 engine を exit 2 にする" "$broken_input_status"

# 8. null は空文字列・0へ変換せず保持する。
run_transform magi-null-preservation magi "$MAGI_FIXTURE"
if [[ "$CASE_EXIT" -eq 0 ]] && jq -e '
  (.findings[] | select(.id == "M-002") | .line) == null
  and (.findings[] | select(.id == "M-002") | .evidence) == null
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "line/evidence の null をそのまま保存する" "$result"

# 9. body の改行・pipe・コードフェンス・引用符を lossless に保持する。
if [[ "$CASE_EXIT" -eq 0 ]] && jq -e '
  .findings[] | select(.id == "M-001") | .body
  | contains("\n")
  and contains("|")
  and contains("\u0060\u0060\u0060")
  and contains("\"")
' "$CASE_RESULT" >/dev/null; then
  result=0
else
  result=1
fi
record_result "複数行 body を jq 経由で壊さず保存する" "$result"

# 10. 大きな body を含む入力でも ARG_MAX に依存せず変換できる。
LARGE_BODY_FILE="$TEST_ROOT/large-body.txt"
head -c 3000000 /dev/zero | tr '\0' 'x' >"$LARGE_BODY_FILE"
MAGI_LARGE_FIXTURE="$TEST_ROOT/magi-large-body.json"
CODEX_LARGE_FIXTURE="$TEST_ROOT/codex-large-body.json"
jq --rawfile body "$LARGE_BODY_FILE" '.findings[0].body = $body' "$MAGI_FIXTURE" >"$MAGI_LARGE_FIXTURE"
jq --rawfile body "$LARGE_BODY_FILE" '.[0].body = $body' "$CODEX_FIXTURE" >"$CODEX_LARGE_FIXTURE"

large_body_status=0
run_transform magi-large-body magi "$MAGI_LARGE_FIXTURE"
if [[ "$CASE_EXIT" -ne 0 ]] || ! validate_artifact "$CASE_RESULT" || ! jq -e '
  any(.findings[]; (.body | length) == 3000000)
' "$CASE_RESULT" >/dev/null; then
  large_body_status=1
fi

run_transform codex-large-body codex "$CODEX_LARGE_FIXTURE"
if [[ "$CASE_EXIT" -ne 0 ]] || ! validate_artifact "$CASE_RESULT" || ! jq -e '
  any(.findings[]; (.body | length) == 3000000)
' "$CASE_RESULT" >/dev/null; then
  large_body_status=1
fi
record_result "3MB の body を含む MAGI/Codex findings table を変換できる" "$large_body_status"

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
