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

  for f in \
    "$ROOT/skills/${persona}/references/output-format.md" \
    "$HOME/.claude/skills/${persona}/references/output-format.md"
  do
    [ -f "$f" ] && FORMAT=$(cat "$f") && break
  done

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
done

echo ""
echo "Results: ${PASS} PASS / ${FAIL} FAIL / ${SKIP} SKIP"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
