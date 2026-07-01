#!/usr/bin/env bash
# knowledge-distill-extract: CONVERSATION 抽出 + Ollama 蒸留 + result ファイル生成
# 引数: $1=RAW_MD_PATH $2=DATE $3=PROJECT $4=TRANSCRIPT_BASE $5=OUTPUT_DIR $6=DISTILL_MODEL
set -euo pipefail

HOOK_DIR="$(dirname "$0")"
# shellcheck source=lib/logging.sh
source "${HOOK_DIR}/lib/logging.sh"
_HOOK_NAME="knowledge-distill"  # ログファイルを orchestrator と統一
_HOOK_LOG="${HOOK_LOG_DIR}/${_HOOK_NAME}.log"

RAW_MD_PATH="$1"
DATE="$2"
PROJECT="$3"
TRANSCRIPT_BASE="$4"
OUTPUT_DIR="$5"
DISTILL_MODEL="$6"

OUTPUT_FILE="${OUTPUT_DIR}/${DATE}-${TRANSCRIPT_BASE}-${PROJECT}.md"

# CONVERSATION 抽出（Raw .md から frontmatter を除去して取得）
CONVERSATION=$(sed '/^---$/,/^---$/d' "$RAW_MD_PATH" | head -c 4000)

if [[ -z "$CONVERSATION" ]]; then
  log_info "empty conversation, skipping"
  exit 0
fi

PROMPT="次の会話から重要な知識を日本語で抽出してください。
出力形式（Markdown）：
## 判明した事実・結論
- 名称と確認日（${DATE}）
重要な知識が含まれない場合は「記録なし」とだけ出力してください。

${CONVERSATION}"

echo "⏳ knowledge-distill: Ollama 推論中 (${DISTILL_MODEL})..." >&2

_OLLAMA_RUN="${HOOK_DIR}/../scripts/ollama-run.sh"
_OLLAMA_EXIT=0
RESULT="$(printf '%s\n' "$PROMPT" | bash "$_OLLAMA_RUN" "$DISTILL_MODEL")" || _OLLAMA_EXIT=$?

if [[ $_OLLAMA_EXIT -ne 0 ]]; then
  log_warn "Ollama 実行失敗 (exit=$_OLLAMA_EXIT)"
  exit 1
fi

echo "  → 推論完了" >&2

if [[ -z "$RESULT" ]] || [[ "$RESULT" == "記録なし" ]]; then
  log_info "no knowledge extracted, skipping"
  exit 0
fi

printf -- '---\ndate: %s\nproject: %s\ntags: [session, auto-distilled]\n---\n# セッション記録 %s %s\n\n%s\n' \
  "$DATE" "$PROJECT" "$DATE" "$TRANSCRIPT_BASE" "$RESULT" > "$OUTPUT_FILE"

log_info "saved: $OUTPUT_FILE"
