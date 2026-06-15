#!/usr/bin/env bash
# test-magi-format.sh — MAGIプロンプトのフォーマット準拠テスト
# Ollamaが起動していない場合はスキップ（CIでは常にパス）

set -euo pipefail

# Ollama起動チェック
if ! ollama list 2>/dev/null >/dev/null; then
  echo "SKIP: Ollama is not running. Skipping MAGI format test."
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ペルソナ定義: name model
declare -A PERSONAS=(
  [melchior]="qwen2.5-coder:7b"
  [balthasar]="phi4:latest"
  [casper]="llama3.1:8b"
  [metatron]="deepseek-r1:8b"
  [sandalphon]="lfm2.5:8b"
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

for persona in "${!PERSONAS[@]}"; do
  model="${PERSONAS[$persona]}"

  # モデル存在チェック
  if ! ollama list 2>/dev/null | grep -q "^${model}"; then
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

  PROMPT="${TASK_BASE}

${TASK_INST}

${CRITERIA}

${FORMAT}

---レビュー対象---
${SAMPLE_DIFF}"

  echo -n "Testing [$persona] ($model)... "

  OUTPUT=$(printf '%s' "$PROMPT" | bash "$HOME/.claude/scripts/ollama-run.sh" "$model" 2>/dev/null || true)

  if echo "$OUTPUT" | grep -qE '###\s+\[(HIGH|MEDIUM|LOW)\]'; then
    echo "PASS"
    ((PASS++)) || true
  else
    echo "FAIL (no [HIGH/MEDIUM/LOW] finding found)"
    echo "--- Output preview (first 10 lines) ---"
    echo "$OUTPUT" | head -10
    echo "---------------------------------------"
    ((FAIL++)) || true
  fi
done

echo ""
echo "Results: ${PASS} PASS / ${FAIL} FAIL / ${SKIP} SKIP"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
