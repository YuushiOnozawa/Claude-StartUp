#!/usr/bin/env bash

# knowledge-distill-register: knowledge-rag 登録
# 引数: $1=OUTPUT_FILE $2=TRANSCRIPT_BASE $3=DATE $4=PROJECT $5=DISTILL_MODEL
set -euo pipefail

HOOK_DIR="$(dirname "$0")"
source "${HOOK_DIR}/lib/logging.sh"

_HOOK_NAME="knowledge-distill"  # ログファイルを orchestrator と統一
_HOOK_LOG="${HOOK_LOG_DIR}/${_HOOK_NAME}.log"

OUTPUT_FILE="$1"
TRANSCRIPT_BASE="$2"
DATE="$3"
PROJECT="$4"
DISTILL_MODEL="$5"

LLM="$HOME/.local/share/knowledge-rag/venv/bin/llm"

if [[ -x "$LLM" ]]; then
  echo "  → knowledge-rag 登録中..." >&2
  KRAG_STRICT="${KRAG_DISTILL_STRICT:-0}"
  KRAG_REL="sessions/${DATE}-${TRANSCRIPT_BASE}-${PROJECT}.md"

  {
    echo "add_documentツールを使って次のMarkdownをknowledge-ragに登録してください。"
    echo "filepath: ${KRAG_REL}"
    echo "category: sessions"
    echo "content:"
    cat "$OUTPUT_FILE"
  } | KNOWLEDGE_RAG_DIR="$HOME/.local/share/knowledge-rag" \
    "$LLM" prompt -m "$DISTILL_MODEL" -T MCP --no-stream \
    >>"$_HOOK_LOG" 2>&1 \
    || [[ "$KRAG_STRICT" != "1" ]]
fi
