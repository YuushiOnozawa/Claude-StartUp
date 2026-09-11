#!/usr/bin/env bash
# scripts/test-execution-budget.sh — Flow/Review 実行時間バジェットの契約テスト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUDGET_JSON="$REPO_ROOT/skills/flow-common/execution-budget.json"
BUDGET_HELPER="$REPO_ROOT/skills/flow-common/execution-budget.sh"
GENERATOR="$REPO_ROOT/skills/flow-common/gen-execution-budget-md.sh"
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

if jq -e '
  .schema_version == "1"
  and (.phases | type == "object" and length == 10)
  and (.derived | type == "object")
  and (.wiring | type == "array" and length > 0)
  and (.policy | type == "object")
' "$BUDGET_JSON" >/dev/null; then
  record_result "JSON のトップレベル schema が正しい" 0
else
  record_result "JSON のトップレベル schema が正しい" 1
fi

if jq -e '
  (.phases.ollama_call_wall_clock | .class == "hard" and .magi == 900 and .codex == 900)
  and (.phases.generation_total | .class == "derived" and .magi == null and .codex == null)
  and (.phases.diff_cap | .class == "gate" and .magi == null and .codex == null
       and .limits.changed_lines == 3200 and .limits.chunks == 8
       and .limits.reject_when == "changed_lines_exceeded AND chunks_exceeded"
       and .limits.soft_warning_lines.minimum == 800
       and .limits.soft_warning_lines.recommended_split_by == 1200)
  and (.phases.casper | .class == "soft" and .magi == 900 and .codex == 900)
  and (.phases.normalizer | .class == "hard" and .magi == 900 and .codex == 900)
  and (.phases.audit | .class == "hard" and .magi == 900 and .codex == null)
  and (.phases.importance | .class == "hard" and .magi == 900 and .codex == null)
  and (.phases.review_post | .class == "mixed" and .magi == 3120 and .codex == 3120
       and .breakdown.api_timeout_seconds == 60
       and .breakdown.page_limit == 10
       and .breakdown.inline_posts_soft_seconds == 1800)
  and (.phases.cleanup | .class == "hard" and .magi == 10 and .codex == 10)
' "$BUDGET_JSON" >/dev/null; then
  record_result "全 phase の分類と backend 値が正本どおりである" 0
else
  record_result "全 phase の分類と backend 値が正本どおりである" 1
fi

if jq -e '
  ["resource_wait","ollama_call_wall_clock","generation_total","diff_cap","casper","normalizer","audit","importance","review_post","cleanup"] as $expected
  | (.phases | keys | sort) == ($expected | sort)
  and all(.phases[];
    has("class") and has("magi") and has("codex") and has("forcing_location") and has("notes")
    and (.class | IN("hard","soft","mixed","derived","gate"))
    and (.magi == null or (.magi | type) == "number")
    and (.codex == null or (.codex | type) == "number")
    and (.forcing_location | type) == "string" and (.forcing_location | length) > 0
    and (.notes | type) == "string" and (.notes | length) > 0)
' "$BUDGET_JSON" >/dev/null; then
  record_result "全 phase と backend、分類、説明キーが完全である" 0
else
  record_result "全 phase と backend、分類、説明キーが完全である" 1
fi

if jq -e '
  .phases.ollama_call_wall_clock.notes | contains("flock 待ち + 推論の合計 wall-clock")
' "$BUDGET_JSON" >/dev/null; then
  record_result "Ollama 予算が待ちと推論の合計 wall-clock と明記されている" 0
else
  record_result "Ollama 予算が待ちと推論の合計 wall-clock と明記されている" 1
fi

MAGI_GENERATION="$(jq -r '.phases.ollama_call_wall_clock.magi * .derived.generation_total.magi.factors.chunk_limit * .derived.generation_total.magi.factors.persona_count' "$BUDGET_JSON")"
CODEX_GENERATION="$(jq -r '.derived.generation_total.codex.factors.chunk_limit * .derived.generation_total.codex.factors.per_chunk_seconds' "$BUDGET_JSON")"
if [[ "$MAGI_GENERATION" -eq 36000 && "$CODEX_GENERATION" -eq 4800 ]] \
  && jq -e '.phases.generation_total.magi == null and .phases.generation_total.codex == null' "$BUDGET_JSON" >/dev/null \
  && ! grep -Eq '(^|[^0-9])(36000|4800|42730|9730)([^0-9]|$)' "$BUDGET_JSON"; then
  record_result "generation_total は式から導出され、導出結果が直書きされていない" 0
else
  record_result "generation_total は式から導出され、導出結果が直書きされていない" 1
fi

calculate_max() {
  local backend="$1"
  local generation="$2"
  jq -r --arg backend "$backend" --argjson generation "$generation" '
    . as $root
    | reduce .derived.max_configured_allowance[$backend].phases[] as $phase (0;
        . + (if $phase == "generation_total" then $generation else ($root.phases[$phase][$backend] // 0) end))
  ' "$BUDGET_JSON"
}

MAGI_MAX="$(calculate_max magi "$MAGI_GENERATION")"
CODEX_MAX="$(calculate_max codex "$CODEX_GENERATION")"
if [[ "$MAGI_MAX" -eq 42730 && "$CODEX_MAX" -eq 9730 ]] \
  && [[ "$($BUDGET_HELPER max-allowance magi)" -eq "$MAGI_MAX" ]] \
  && [[ "$($BUDGET_HELPER max-allowance codex)" -eq "$CODEX_MAX" ]] \
  && jq -e '.derived.max_configured_allowance.magi.phases | index("casper") != null' "$BUDGET_JSON" >/dev/null; then
  record_result "max_configured_allowance は soft phase を含む式から算出される" 0
else
  record_result "max_configured_allowance は soft phase を含む式から算出される" 1
fi

OVERRIDE_JSON="$TEST_ROOT/execution-budget.json"
jq '.phases.ollama_call_wall_clock.magi = 2' "$BUDGET_JSON" > "$OVERRIDE_JSON"
TIMEOUT_EXIT=0
V="$(EXECUTION_BUDGET_JSON="$OVERRIDE_JSON" "$BUDGET_HELPER" get ollama_call_wall_clock magi)"
timeout "$V" sleep 5 || TIMEOUT_EXIT=$?
if [[ "$TIMEOUT_EXIT" -eq 124 ]]; then
  record_result "override JSON の小さい値で実コマンドが timeout 124 になる" 0
else
  record_result "override JSON の小さい値で実コマンドが timeout 124 になる" 1
fi

WIRED_LINE="$(rg -m1 'OLLAMA_KEEP_ALIVE=.*timeout "\$OLLAMA_BUDGET" bash ' \
  "$REPO_ROOT/skills/magi-common/references/execution-steps.md" || true)"
WIRED_COMMAND="$(sed -E 's#bash ~/.claude/scripts/ollama-run\.sh.*#sleep 5#' <<<"$WIRED_LINE")"
WIRED_EXIT=0
OLLAMA_BUDGET="$V" bash -c "$WIRED_COMMAND" || WIRED_EXIT=$?
if [[ -n "$WIRED_LINE" && "$WIRED_EXIT" -eq 124 ]]; then
  record_result "実手順から抽出した timeout コマンドが helper override 値を使う" 0
else
  record_result "実手順から抽出した timeout コマンドが helper override 値を使う" 1
fi

extract_first_bash_after_heading() {
  local heading="$1" source="$2" output="$3"
  awk -v heading="$heading" '
    index($0, heading) == 1 { found=1; next }
    found && /^```bash$/ { in_block=1; next }
    in_block && /^```$/ { exit }
    in_block { print }
  ' "$source" > "$output"
}

printf '%s\n' 'setTimeout(() => {}, 5000);' > "$TEST_ROOT/slow.mjs"
mkdir -p "$TEST_ROOT/plugin/scripts" "$TEST_ROOT/plugin/skills/flow-common"
cp "$REPO_ROOT/scripts/codex-broker-run.sh" "$TEST_ROOT/plugin/scripts/codex-broker-run.sh"
cp "$BUDGET_HELPER" "$TEST_ROOT/plugin/skills/flow-common/execution-budget.sh"
for kind in audit importance; do
  upper="${kind^^}"
  snippet="$TEST_ROOT/$kind-step5.sh"
  extract_first_bash_after_heading "## ステップ 5: Codex 呼び出し" \
    "$REPO_ROOT/skills/magi-common/references/codex-$kind.md" "$snippet"
  case_dir="$TEST_ROOT/$kind-timeout"
  mkdir -p "$case_dir"
  kind_override="$TEST_ROOT/$kind-budget.json"
  jq --arg kind "$kind" '.phases[$kind].magi = 1' "$BUDGET_JSON" > "$kind_override"
  mkdir -p "$case_dir/slow-runtime" "$case_dir/fail-runtime"
  cp "$TEST_ROOT/slow.mjs" "$TEST_ROOT/plugin/scripts/codex-companion.mjs"
  snippet_output="$(cd "$REPO_ROOT" && MAGI_TMPDIR="$case_dir" CLAUDE_PLUGIN_ROOT="$TEST_ROOT/plugin" \
    CODEX_BROKER_RUN="$TEST_ROOT/plugin/scripts/codex-broker-run.sh" \
    EXECUTION_BUDGET_JSON="$kind_override" XDG_RUNTIME_DIR="$case_dir/slow-runtime" bash "$snippet")"
  result_file="$case_dir/codex-$kind.json"
  if [[ "$snippet_output" == *"${upper}_SKIPPED"* && ! -e "$result_file" ]] \
    && ! rg -q 'return 0' "$snippet"; then
    record_result "$kind timeout は top-level で成功終了し結果 JSON を生成しない" 0
  else
    record_result "$kind timeout は top-level で成功終了し結果 JSON を生成しない" 1
  fi

  printf '%s\n' 'process.exit(7);' > "$TEST_ROOT/fail.mjs"
  cp "$TEST_ROOT/fail.mjs" "$TEST_ROOT/plugin/scripts/codex-companion.mjs"
  rm -f -- "$result_file"
  (cd "$REPO_ROOT" && MAGI_TMPDIR="$case_dir" CLAUDE_PLUGIN_ROOT="$TEST_ROOT/plugin" \
    CODEX_BROKER_RUN="$TEST_ROOT/plugin/scripts/codex-broker-run.sh" \
    EXECUTION_BUDGET_JSON="$kind_override" XDG_RUNTIME_DIR="$case_dir/fail-runtime" bash "$snippet") >/dev/null
  if jq -e --arg error "${upper}_ERROR" '.error == $error' "$result_file" >/dev/null 2>&1; then
    record_result "$kind の timeout 以外の失敗は ERROR JSON を生成する" 0
  else
    record_result "$kind の timeout 以外の失敗は ERROR JSON を生成する" 1
  fi
done

TAKEOVER_JSON="$TEST_ROOT/takeover.json"
jq '.policy.auto_takeover = true' "$BUDGET_JSON" > "$TAKEOVER_JSON"
if EXECUTION_BUDGET_JSON="$TAKEOVER_JSON" "$BUDGET_HELPER" assert-no-takeover >/dev/null 2>&1; then
  record_result "soft phase がある auto_takeover=true fixture を拒否する" 1
else
  record_result "soft phase がある auto_takeover=true fixture を拒否する" 0
fi
if "$BUDGET_HELPER" assert-no-takeover; then
  record_result "正本の auto_takeover=false を受け入れる" 0
else
  record_result "正本の auto_takeover=false を受け入れる" 1
fi

NULL_EXIT=0
NULL_OUTPUT="$($BUDGET_HELPER get audit codex)" || NULL_EXIT=$?
if [[ "$NULL_EXIT" -eq 3 && -z "$NULL_OUTPUT" ]] \
  && [[ "$($BUDGET_HELPER get cleanup magi)" -eq 10 ]] \
  && [[ "$($BUDGET_HELPER list | wc -l)" -eq 10 ]]; then
  record_result "helper の get null 契約と list 出力が正しい" 0
else
  record_result "helper の get null 契約と list 出力が正しい" 1
fi

OLLAMA_FLOCK_VALUE="$(sed -nE 's/.*flock -w ([0-9]+) -E 9 9.*/\1/p' "$REPO_ROOT/scripts/ollama-run.sh")"
if [[ "$OLLAMA_FLOCK_VALUE" == "$(jq -r '.phases.ollama_call_wall_clock.magi' "$BUDGET_JSON")" ]]; then
  record_result "ollama-run.sh の flock -w literal が JSON 正本と一致する" 0
else
  record_result "ollama-run.sh の flock -w literal が JSON 正本と一致する" 1
fi

FALLBACK_FAILURES=0
check_fallback() {
  local file="$1" variable="$2" expected="$3"
  local needle=": \"\${${variable}:=${expected}}\""
  grep -Fq "$needle" "$REPO_ROOT/$file" || {
    echo "fallback drift: $file $variable=$expected" >&2
    FALLBACK_FAILURES=$((FALLBACK_FAILURES + 1))
  }
}
while IFS= read -r wiring_row; do
  wiring_json="$(base64 -d <<<"$wiring_row")"
  file="$(jq -r '.file' <<<"$wiring_json")"
  variable="$(jq -r '.variable' <<<"$wiring_json")"
  mapfile -t helper_args < <(jq -r '.helper_args[]' <<<"$wiring_json")
  expected="$($BUDGET_HELPER "${helper_args[@]}")"
  if [[ "$file" == "scripts/codex-broker-run.sh" && "$variable" == "RESOURCE_WAIT" ]]; then
    if ! grep -Fq 'RESOURCE_WAIT=900' "$REPO_ROOT/$file"; then
      echo "fallback drift: $file $variable=900" >&2
      FALLBACK_FAILURES=$((FALLBACK_FAILURES + 1))
    fi
  else
    check_fallback "$file" "$variable" "$expected"
  fi
  if ! grep -Fq "bash \"\$BUDGET_HELPER\" ${helper_args[*]}" "$REPO_ROOT/$file"; then
    echo "helper wiring drift: $file ${helper_args[*]}" >&2
    FALLBACK_FAILURES=$((FALLBACK_FAILURES + 1))
  fi
done < <(jq -r '.wiring[] | @base64' "$BUDGET_JSON")
if [[ "$FALLBACK_FAILURES" -eq 0 ]]; then
  record_result "全 fallback 既定値が JSON から生成した期待値と一致する" 0
else
  record_result "全 fallback 既定値が JSON から生成した期待値と一致する" 1
fi

if ! rg -n 'timeout +(900|1800|60)( |$)|for PAGE in \{1\.\.10\}' \
    "$REPO_ROOT/skills/magi-common/references/execution-steps.md" \
    "$REPO_ROOT/skills/magi-common/references/normalizer.md" \
    "$REPO_ROOT/skills/magi-common/references/codex-audit.md" \
    "$REPO_ROOT/skills/magi-common/references/codex-importance.md" \
    "$REPO_ROOT/skills/flow-common/references/review-post.md" >/dev/null \
  && [[ "$($BUDGET_HELPER diff-cap changed_lines)" -eq "$(jq -r '.phases.diff_cap.limits.changed_lines' "$BUDGET_JSON")" ]] \
  && [[ "$($BUDGET_HELPER diff-cap chunks)" -eq "$(jq -r '.phases.diff_cap.limits.chunks' "$BUDGET_JSON")" ]] \
  && [[ "$($BUDGET_HELPER diff-cap soft_warning)" -eq "$(jq -r '.phases.diff_cap.limits.soft_warning_lines.minimum' "$BUDGET_JSON")" ]] \
  && [[ "$($BUDGET_HELPER review-post api_timeout)" -eq "$(jq -r '.phases.review_post.breakdown.api_timeout_seconds' "$BUDGET_JSON")" ]] \
  && [[ "$($BUDGET_HELPER review-post page_limit)" -eq "$(jq -r '.phases.review_post.breakdown.page_limit' "$BUDGET_JSON")" ]] \
  && [[ "$($BUDGET_HELPER review-post inline_soft)" -eq "$(jq -r '.phases.review_post.breakdown.inline_posts_soft_seconds' "$BUDGET_JSON")" ]] \
  && [[ "$($BUDGET_HELPER generation-factor per_chunk_seconds codex)" -eq "$(jq -r '.derived.generation_total.codex.factors.per_chunk_seconds' "$BUDGET_JSON")" ]]; then
  record_result "全予算コマンドが helper 経由で正本値へ配線されている" 0
else
  record_result "全予算コマンドが helper 経由で正本値へ配線されている" 1
fi

if rg -q 'if ! .*magi-split-hunk\.sh.*>.*DIFF_CAP_CHUNKS_FILE' "$REPO_ROOT/skills/magi-hard/SKILL.md" \
  && rg -q 'if ! .*magi-split-hunk\.sh.*>.*DIFF_CAP_CHUNKS_FILE' "$REPO_ROOT/skills/dev-flow-fast/references/codex-review-hard.md" \
  && ! rg -q 'magi-split-hunk\.sh.*\| *grep -c' "$REPO_ROOT/skills/magi-hard/SKILL.md" \
  && ! rg -q 'magi-split-hunk\.sh.*\| *grep -c' "$REPO_ROOT/skills/dev-flow-fast/references/codex-review-hard.md"; then
  record_result "両 diff cap gate が splitter 終了コード確認後にチャンクを数える" 0
else
  record_result "両 diff cap gate が splitter 終了コード確認後にチャンクを数える" 1
fi

GENERATED_MD="$TEST_ROOT/execution-budget.md"
EXECUTION_BUDGET_JSON="$TEST_ROOT/does-not-exist.json" "$GENERATOR" --output "$GENERATED_MD"
if cmp -s "$GENERATED_MD" "$REPO_ROOT/skills/flow-common/references/execution-budget.md"; then
  record_result "Markdown 生成器が冪等である" 0
else
  record_result "Markdown 生成器が冪等である" 1
fi

CUSTOM_JSON="$TEST_ROOT/custom-budget.json"
CUSTOM_MD="$TEST_ROOT/custom-budget.md"
jq '.phases.normalizer.magi = 901' "$BUDGET_JSON" > "$CUSTOM_JSON"
"$GENERATOR" --input "$CUSTOM_JSON" --output "$CUSTOM_MD"
if grep -Fq '| `normalizer` | hard | 901s |' "$CUSTOM_MD"; then
  record_result "Markdown 生成器の --input/--output が明示した入出力だけを使う" 0
else
  record_result "Markdown 生成器の --input/--output が明示した入出力だけを使う" 1
fi

SYNTAX_FAILED=0
for script in \
  "$REPO_ROOT/scripts/ollama-run.sh" \
  "$REPO_ROOT/scripts/test-execution-budget.sh" \
  "$BUDGET_HELPER" \
  "$GENERATOR"; do
  bash -n "$script" || SYNTAX_FAILED=1
done
if [[ "$SYNTAX_FAILED" -eq 0 ]]; then
  record_result "対象シェルスクリプトが bash -n を通る" 0
else
  record_result "対象シェルスクリプトが bash -n を通る" 1
fi

echo
echo "Results: $PASS PASS, $FAIL FAIL"
[[ "$FAIL" -eq 0 ]]
