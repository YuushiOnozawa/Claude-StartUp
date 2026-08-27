#!/usr/bin/env bash
# scripts/test-casper-engine-contract.sh — CASPER engine 共通契約の参照テスト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE_REF="skills/flow-common/references/casper-engine.md"
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

extract_code_block() {
  local heading="$1"
  local source_file="$2"
  local output_file="$3"
  local block_number="${4:-1}"
  awk -v heading="$heading" -v block_number="$block_number" '
    index($0, heading) == 1 { found=1; next }
    found && /^```bash$/ {
      block_count++
      in_block=(block_count == block_number)
      next
    }
    found && in_block && /^```$/ { exit }
    found && in_block { print }
  ' "$source_file" >"$output_file"
}

run_structure_check() {
  local normalized_file="$1"
  NORMALIZED_FILE="$normalized_file" bash "$STRUCTURE_SNIPPET" >/dev/null 2>&1
}

STRUCTURE_SNIPPET="$TEST_ROOT/casper-structure.sh"
extract_code_block "## Normalizer と構造検証" "$REPO_ROOT/$ENGINE_REF" "$STRUCTURE_SNIPPET"
if [[ -s "$STRUCTURE_SNIPPET" ]]; then
  record_result "casper-engine.md の構造検証コードブロックを抽出できる" 0
else
  record_result "casper-engine.md の構造検証コードブロックを抽出できる" 1
fi

VALID_NORMALIZED="$TEST_ROOT/normalized-valid.json"
printf '%s\n' '[{"persona":"CASPER","path":"src/a.sh","line":1,"headline":"headline","body":"body","evidence":null}]' >"$VALID_NORMALIZED"
CONCAT_INVALID_VALID="$TEST_ROOT/normalized-invalid-valid.json"
printf '%s\n%s\n' '{"invalid":true}' "$(<"$VALID_NORMALIZED")" >"$CONCAT_INVALID_VALID"
CONCAT_VALID_VALID="$TEST_ROOT/normalized-valid-valid.json"
printf '%s\n%s\n' "$(<"$VALID_NORMALIZED")" "$(<"$VALID_NORMALIZED")" >"$CONCAT_VALID_VALID"

if run_structure_check "$VALID_NORMALIZED"; then
  result=0
else
  result=1
fi
record_result "単一の正常なJSON配列を構造検証で受け入れる" "$result"

if run_structure_check "$CONCAT_INVALID_VALID"; then
  result=1
else
  result=0
fi
record_result "不正な配列と正常な配列の連結JSON値を拒否する" "$result"

if run_structure_check "$CONCAT_VALID_VALID"; then
  result=1
else
  result=0
fi
record_result "正常な配列の連結JSON値を拒否する" "$result"

run_path_validation_case() {
  local mode="$1"
  local heading="$2"
  local case_dir="$TEST_ROOT/casper-path-$mode"
  local snippet="$case_dir/casper-step.sh"
  local runner="$case_dir/run.sh"
  local audit_file="$case_dir/audit.json"
  local self_tamper_file="$case_dir/self-tamper.json"
  local adjudication_file="$case_dir/adjudication.json"
  local runner_exit=0
  mkdir -p "$case_dir"
  if [[ "$mode" == "fast" ]]; then
    extract_code_block "$heading" "$REPO_ROOT/skills/dev-flow-fast/references/codex-review-${mode}.md" "$snippet" 2
  else
    extract_code_block "$heading" "$REPO_ROOT/skills/dev-flow-fast/references/codex-review-${mode}.md" "$snippet"
  fi
  printf '%s\n' '[]' >"$case_dir/findings-table.json"
  printf '%s\n' 'src/allowed.sh' >"$case_dir/targets.txt"
  printf '%s\n' '[{"source_persona":"CASPER","path":"src/allowed.sh","line":1,"headline":"allowed","body":"body"},{"source_persona":"CASPER","path":"src/outside.sh","line":2,"headline":"outside","body":"body"}]' >"$case_dir/casper-normalized.json"
  printf '%s\n' '[]' >"$audit_file"
  printf '%s\n' 'false' >"$self_tamper_file"
  if [[ "$mode" == "hard" ]]; then
    printf '%s\n' '{"artifact_type":"review-adjudication","schema_version":"1","validity_global_failure":false,"results":[]}' >"$adjudication_file"
  else
    printf '%s\n' '[]' >"$adjudication_file"
  fi
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    printf 'REVIEW_TMPDIR=%q\n' "$case_dir"
    printf 'TARGETS_FILE=%q\n' "$case_dir/targets.txt"
    printf 'CASPER_NORMALIZED_FILE=%q\n' "$case_dir/casper-normalized.json"
    printf 'FINDINGS_TABLE_FILE=%q\n' "$case_dir/findings-table.json"
    printf '%s\n' 'CASPER_ENGINE_STATUS=complete' 'NEXT_ID=1' "FAILED_PERSONAS_JSON='[\"MELCHIOR\"]'"
    cat "$snippet"
  } >"$runner"
  chmod +x "$runner"
  if bash "$runner"; then
    runner_exit=0
  else
    runner_exit=$?
  fi
  if [[ "$runner_exit" -eq 0 ]] \
    && jq -e 'length == 0' "$case_dir/findings-table.json" >/dev/null 2>&1 \
    && jq -e '. == ["MELCHIOR", "CASPER"]' "$case_dir/failed-personas.json" >/dev/null 2>&1; then
    result=0
  else
    result=1
  fi
  record_result "/codex-${mode} は対象外path混在時にCASPER findingを全件統合せず失敗記録する" "$result"
  if [[ "$mode" == "hard" ]]; then
    bash "$REPO_ROOT/scripts/codex-review-merge.sh" --mode hard \
      "$case_dir/findings-table.json" "$audit_file" "$self_tamper_file" \
      "$case_dir/failed-personas.json" "$adjudication_file" \
      >"$case_dir/merge-result.json" 2>"$case_dir/merge.stderr" || true
  else
    bash "$REPO_ROOT/scripts/codex-review-merge.sh" --mode fast \
      "$case_dir/findings-table.json" "$audit_file" "$self_tamper_file" \
      "$case_dir/failed-personas.json" \
      >"$case_dir/merge-result.json" 2>"$case_dir/merge.stderr" || true
  fi
  if jq -e '.pipeline_status == "incomplete" and (.failed_personas | index("CASPER")) != null' \
    "$case_dir/merge-result.json" >/dev/null 2>&1; then
    result=0
  else
    result=1
  fi
  record_result "/codex-${mode} の対象外path fail-closed 結果がpipeline_status=incompleteになる" "$result"
}

run_path_validation_case fast "## ステップ 5:"
run_path_validation_case hard "## ステップ 9:"

for file in \
  "$REPO_ROOT/skills/magi-fast/SKILL.md" \
  "$REPO_ROOT/skills/magi-hard/SKILL.md" \
  "$REPO_ROOT/skills/dev-flow-fast/references/codex-review-hard.md" \
  "$REPO_ROOT/skills/dev-flow-fast/references/codex-review-fast.md"; do
  if grep -Fq "$ENGINE_REF" "$file"; then
    record_result "$(realpath --relative-to="$REPO_ROOT" "$file") が CASPER engine 契約を参照する" 0
  else
    record_result "$(realpath --relative-to="$REPO_ROOT" "$file") が CASPER engine 契約を参照する" 1
  fi
done

FAST_FILE="$REPO_ROOT/skills/dev-flow-fast/references/codex-review-fast.md"
if grep -Eiq 'codex-review-hard\.md[^\n]*(hardの)?[[:space:]]*ステップ[[:space:]]*[679]' "$FAST_FILE"; then
  record_result "codex-review-fast.md に CASPER の hard ステップ番号参照が残っていない" 1
else
  record_result "codex-review-fast.md に CASPER の hard ステップ番号参照が残っていない" 0
fi

if grep -RFn --include='*' -- 'agents/casper.md' "$REPO_ROOT/skills" >/dev/null 2>&1; then
  record_result "skills/ 配下に agents/casper.md 参照が残っていない" 1
else
  record_result "skills/ 配下に agents/casper.md 参照が残っていない" 0
fi

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
