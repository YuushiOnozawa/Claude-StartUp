#!/usr/bin/env bash
# test-magi-format.sh — MAGIプロンプトのフォーマット準拠テスト
# Ollamaが起動していない場合はスキップ（CIでは常にパス）

set -euo pipefail

# Ollama起動チェック
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_OLLAMA_SH="$_SCRIPT_DIR/../hooks/lib/ollama.sh"
# shellcheck source=../hooks/lib/ollama.sh
[[ -f "$_OLLAMA_SH" ]] || { echo "Error: ollama.sh not found: $_OLLAMA_SH" >&2; exit 1; }
source "$_OLLAMA_SH"

OLLAMA_TAGS_JSON=""
if ! OLLAMA_TAGS_JSON="$(curl -sf --max-time 5 "$(ollama_base_url)/api/tags" 2>/dev/null)"; then
  echo "SKIP: Ollama is not running. Skipping MAGI format test."
  exit 0
fi
OLLAMA_MODELS="$(printf '%s' "$OLLAMA_TAGS_JSON" | jq -r '.models[]?.name' 2>/dev/null || true)"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OLLAMA_RUN=""
for f in \
  "$ROOT/scripts/ollama-run.sh" \
  "$HOME/.claude/scripts/ollama-run.sh"
do
  [ -f "$f" ] && OLLAMA_RUN="$f" && break
done
if [ -z "$OLLAMA_RUN" ]; then
  echo "Error: ollama-run.sh not found" >&2
  exit 2
fi

# ペルソナ定義: name model
# CASPER は Ollama を使わず Haiku を標準モデルとするため含めない（skills/casper/SKILL.md）
declare -A PERSONAS=(
  [melchior]="qwen2.5-coder:7b"
  [balthasar]="gemma4:e4b-it-qat"
  [metatron]="devstral:latest"
  [sandalphon]="granite3.3:8b"
  [leliel]="lfm2.5:8b"
)

# サンプル差分（意図的なバグを含む）
SAMPLE_DIFF='diff --git a/scripts/deploy.sh b/scripts/deploy.sh
index 0000000..1234567 100644
--- a/scripts/deploy.sh
+++ b/scripts/deploy.sh
@@ -1,5 +1,10 @@
 #!/usr/bin/env bash
+FILE_PATH=$1
+eval "rm -rf $FILE_PATH"
+API_KEY="sk-hardcoded-secret-12345"
+git commit -m "deploy"
+DROP TABLE users;'

PASS=0
FAIL=0
SKIP=0

DEFAULT_OUTPUT_FORMAT_PATH="skills/magi-common/references/output-format.md"

extract_output_format_path() {
  local skill_file="$1"

  awk -F '|' '
    $2 ~ /^[[:space:]]*OUTPUT_FORMAT_PATH[[:space:]]*$/ {
      if (match($3, /`[^`]+`/)) {
        print substr($3, RSTART + 1, RLENGTH - 2)
        exit
      }
    }
  ' "$skill_file"
}

resolve_output_format_path() {
  local persona="$1"
  local skill_file=""
  local output_format_path_value=""
  local f

  for f in \
    "$ROOT/skills/${persona}/SKILL.md" \
    "$HOME/.claude/skills/${persona}/SKILL.md"
  do
    [ -f "$f" ] && skill_file="$f" && break
  done

  if [ -n "$skill_file" ]; then
    output_format_path_value="$(extract_output_format_path "$skill_file")"
  fi

  if [ -z "$output_format_path_value" ]; then
    output_format_path_value="$DEFAULT_OUTPUT_FORMAT_PATH"
  fi

  printf '%s' "$output_format_path_value"
}

validate_v2_output() {
  awk '
    {
      lines[NR] = $0
    }

    function next_nonempty(start, i) {
      for (i = start; i <= NR; i++) {
        if (lines[i] !~ /^[[:space:]]*$/) {
          return i
        }
      }
      return 0
    }

    function print_location_block(start, i) {
      print "--- Invalid Location block ---"
      for (i = start; i <= NR; i++) {
        if (i > start && lines[i] ~ /^Location:/) {
          break
        }
        print lines[i]
        if (i > start && lines[i] ~ /^[[:space:]]*$/) {
          break
        }
      }
    }

    END {
      for (i = 1; i <= NR; i++) {
        if (lines[i] ~ /^Location:/) {
          location_count++
          problem_idx = next_nonempty(i + 1)
          breakage_idx = problem_idx ? next_nonempty(problem_idx + 1) : 0

          if (!problem_idx || lines[problem_idx] !~ /^Problem:/ || !breakage_idx || lines[breakage_idx] !~ /^Breakage:/) {
            invalid_count++
            print_location_block(i)
          }
        }
      }

      if (location_count == 0) {
        exit 2
      }
      if (invalid_count > 0) {
        exit 1
      }

      printf "%d\n", location_count
    }
  '
}

# IMPACT_CONTEXT は repo 全体を検索するため、必要有無にかかわらず一度だけ生成する。
IMPACT_CONTEXT="$(bash "$ROOT/scripts/magi-impact-context.sh" "$SAMPLE_DIFF" 2>/dev/null || true)"

for persona in "${!PERSONAS[@]}"; do
  model="${PERSONAS[$persona]}"

  # モデル存在チェック
  if ! printf '%s\n' "$OLLAMA_MODELS" | grep -Fxq -- "$model"; then
    echo "SKIP [$persona]: model $model not found"
    ((SKIP++)) || true
    continue
  fi

  # プロンプト組み立て
  TASK_BASE=""
  TASK_INST=""
  CRITERIA=""
  FORMAT=""
  OUTPUT_FORMAT_PATH_VALUE="$(resolve_output_format_path "$persona")"

  for f in \
    "$ROOT/skills/magi-common/references/task-base.md" \
    "$HOME/.claude/skills/magi-common/references/task-base.md"
  do
    [ -f "$f" ] && TASK_BASE=$(cat "$f") && break
  done

  for f in \
    "$ROOT/skills/${persona}/references/task-instruction.md" \
    "$HOME/.claude/skills/${persona}/references/task-instruction.md"
  do
    [ -f "$f" ] && TASK_INST=$(cat "$f") && break
  done

  for f in \
    "$ROOT/skills/${persona}/references/review-criteria.md" \
    "$HOME/.claude/skills/${persona}/references/review-criteria.md"
  do
    [ -f "$f" ] && CRITERIA=$(cat "$f") && break
  done

  if [[ "$OUTPUT_FORMAT_PATH_VALUE" = /* ]]; then
    [ -f "$OUTPUT_FORMAT_PATH_VALUE" ] && FORMAT=$(cat "$OUTPUT_FORMAT_PATH_VALUE")
  else
    for f in \
      "$ROOT/$OUTPUT_FORMAT_PATH_VALUE" \
      "$HOME/.claude/$OUTPUT_FORMAT_PATH_VALUE"
    do
      [ -f "$f" ] && FORMAT=$(cat "$f") && break
    done
  fi

  IMPACT_BLOCK=""
  if grep -q "IMPACT_CONTEXT" <<< "$TASK_INST"; then
    if [ -z "$IMPACT_CONTEXT" ]; then
      echo "SKIP [$persona]: IMPACT_CONTEXT not generated"
      ((SKIP++)) || true
      continue
    fi
    IMPACT_BLOCK="
<IMPACT_CONTEXT>
${IMPACT_CONTEXT}
</IMPACT_CONTEXT>
"
  fi

  PROMPT="${TASK_BASE}

${TASK_INST}

${CRITERIA}

${FORMAT}${IMPACT_BLOCK}

---レビュー対象---
${SAMPLE_DIFF}"

  echo -n "Testing [$persona] ($model)... "

  OUTPUT=$(printf '%s' "$PROMPT" | bash "$OLLAMA_RUN" "$model" 2>/dev/null || true)

  if [[ "$OUTPUT_FORMAT_PATH_VALUE" == *output-format-v2.md ]]; then
    LEGACY_HEADINGS=$(printf '%s\n' "$OUTPUT" | grep '^###' || true)

    if [ -n "$LEGACY_HEADINGS" ]; then
      echo "FAIL (legacy ### headings)"
      echo "--- Legacy ### headings ---"
      printf '%s\n' "$LEGACY_HEADINGS"
      ((FAIL++)) || true
    elif [[ "$OUTPUT" =~ ^[[:space:]]*No\ findings\.[[:space:]]*$ ]]; then
      echo "PASS (0 candidates)"
      ((PASS++)) || true
    elif V2_CANDIDATE_COUNT=$(printf '%s\n' "$OUTPUT" | validate_v2_output); then
      echo "PASS (${V2_CANDIDATE_COUNT} candidates)"
      ((PASS++)) || true
    else
      V2_STATUS=$?
      if [ "$V2_STATUS" -eq 2 ]; then
        echo "FAIL (no Location blocks and not No findings.)"
      else
        echo "FAIL (invalid Location block)"
        printf '%s\n' "$V2_CANDIDATE_COUNT"
      fi
      ((FAIL++)) || true
    fi
  else

  HEADING_RE='^###[[:space:]]+\[(HIGH|MEDIUM|LOW)\][[:space:]]+[^[:space:]]+:[0-9]+(-[0-9]+)?[[:space:]]+—[[:space:]]+.+$'
  HEADINGS=$(printf '%s\n' "$OUTPUT" | grep '^###' || true)
  HEADING_COUNT=$(printf '%s\n' "$HEADINGS" | grep -c '^###' || true)
  VALID_COUNT=$(printf '%s\n' "$HEADINGS" | grep -Ec "$HEADING_RE" || true)
  INVALID_HEADINGS=$(printf '%s\n' "$HEADINGS" | grep -Ev "$HEADING_RE" || true)
  INVALID_COUNT=$(printf '%s\n' "$INVALID_HEADINGS" | grep -c '^###' || true)

  if [ "$VALID_COUNT" -gt 0 ] && [ "$INVALID_COUNT" -eq 0 ]; then
    echo "PASS"
    ((PASS++)) || true
  else
    echo "FAIL (${INVALID_COUNT}/${HEADING_COUNT} invalid ### headings; ${VALID_COUNT} valid)"
    if [ "$INVALID_COUNT" -gt 0 ]; then
      echo "--- Invalid ### headings ---"
      printf '%s\n' "$INVALID_HEADINGS"
    fi
    echo "---------------------------------------"
    ((FAIL++)) || true
  fi
  fi
done

echo ""
echo "Results: ${PASS} PASS / ${FAIL} FAIL / ${SKIP} SKIP"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
