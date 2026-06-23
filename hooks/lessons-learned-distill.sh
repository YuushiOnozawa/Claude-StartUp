#!/usr/bin/env bash
# lessons-learned-distill: SessionEnd hook — orchestrator
# Detects mistakes in session transcripts via Ollama and saves to Obsidian.
set -euo pipefail
# 終了コード方針（カテゴリ B / Issue #51）:
#   exit 0 — 想定内スキップ（transcript なし・会話内容なし）、またはキュー追加（pCloud/Ollama 条件・成否問わず）
#   非ゼロ  — 想定外エラー（set -euo pipefail による自動終了。Claude Code ログに記録）

HOOK_DIR="$(dirname "$0")"
# shellcheck source=lib/logging.sh
source "${HOOK_DIR}/lib/logging.sh"
# shellcheck source=lib/queue.sh
source "${HOOK_DIR}/lib/queue.sh"
# shellcheck source=lib/ollama.sh
source "${HOOK_DIR}/lib/ollama.sh"
HOOK_NAME="lessons-learned"

# Ollama 起動確認（スクリプト全体で共有）
_OLLAMA_UP=0
ollama_is_up && _OLLAMA_UP=1 || true

# キュードレイン（リトライ実行時はスキップして無限ループを防ぐ）
if [[ "${KRAG_LL_RETRY:-0}" != "1" ]] && mountpoint -q "$HOME/pcloud"; then
  _ll_retry_callback() {
    local item_file="$1"
    local t c
    t=$(jq -e -r '.transcript_path // empty' "$item_file" 2>/dev/null) || { log_error "failed to read transcript_path from $item_file"; return 1; }
    c=$(jq -r '.cwd // ""' "$item_file" 2>/dev/null) || true
    log_info "retrying queued item: $(basename "$t")"
    jq -n --arg transcript_path "$t" --arg cwd "$c" \
      '{"transcript_path":$transcript_path,"cwd":$cwd}' \
      | KRAG_LL_RETRY=1 bash "${_LL_HOOK_DIR}/lessons-learned-distill.sh"
  }
  _LL_HOOK_DIR="$HOOK_DIR"
  _cnt=$(queue_count "$HOOK_NAME" 2>/dev/null)
  if [[ ${_cnt:-0} -gt 0 ]]; then
    echo "⏳ lessons-learned: 保留キュー ${_cnt} 件をリトライ中..." >&2
  fi
  queue_drain "$HOOK_NAME" "" "_ll_retry_callback"
fi

# Read SessionEnd JSON from stdin
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  log_info "no transcript, skipping"
  exit 0
fi

# CONVERSATION 空チェック（早期終了）
CONVERSATION=$(jq -rn '
  [inputs |
    ((.role // .type // "") | ascii_downcase) as $r |
    (
      (.msg.content // .content // "") |
      if type == "array" then map(select(.type == "text") | .text) | join(" ")
      elif type == "string" then .
      else "" end
    ) as $text |
    if ($r == "human" or $r == "user") and ($text | length) > 0 then "x"
    elif $r == "assistant" and ($text | length) > 0 then "x"
    else empty end
  ] | length
' "$TRANSCRIPT_PATH" 2>/dev/null)
if [[ -z "$CONVERSATION" ]] || [[ "$CONVERSATION" -eq 0 ]]; then
  log_info "empty conversation, skipping"
  exit 0
fi

# Metadata
PROJECT_CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"' 2>/dev/null)
PROJECT=$(basename "$PROJECT_CWD" 2>/dev/null || echo "unknown")
DATE=$(date +%Y-%m-%d)
OUTPUT_DIR="$HOME/pcloud/obsidian"

# pCloud マウント確認
if ! mountpoint -q "$HOME/pcloud"; then
  log_error "pCloud not mounted"
  echo "  ⏳ lessons-learned: pCloud 未マウント → 保留 ($PROJECT)" >&2
  if queue_push "$HOOK_NAME" "pcloud" "$TRANSCRIPT_PATH" "$PROJECT_CWD"; then
    log_info "queued for retry: $TRANSCRIPT_PATH"
  else
    log_error "queue_push failed"
  fi
  exit 0
fi

mkdir -p "${OUTPUT_DIR}/lessons-learned"

# Ollama 起動確認
if [[ $_OLLAMA_UP -eq 0 ]]; then
  log_warn "Ollama not running, queuing for retry"
  if [[ "${KRAG_LL_RETRY:-0}" == "1" ]]; then
    exit 1
  fi
  echo "  ⏳ lessons-learned: Ollama 未起動 → 保留 ($PROJECT)" >&2
  if queue_push "$HOOK_NAME" "ollama" "$TRANSCRIPT_PATH" "$PROJECT_CWD"; then
    log_info "queued for retry (ollama): $TRANSCRIPT_PATH"
  else
    log_error "queue_push failed"
  fi
  exit 0
fi

# 使用モデルを解決
_KRAG_MODEL_FILE="$HOME/.local/share/knowledge-rag/model"
_DISTILL_MODEL="$(ollama_best_model "$_KRAG_MODEL_FILE")"

# ミス検知実行（lessons-learned-extract.sh に委譲）
_EXTRACT_EXIT=0
bash "${HOOK_DIR}/lessons-learned-extract.sh" \
  "$TRANSCRIPT_PATH" "$DATE" "$PROJECT" "$OUTPUT_DIR" "$_DISTILL_MODEL" \
  || _EXTRACT_EXIT=$?

if [[ $_EXTRACT_EXIT -ne 0 ]]; then
  log_warn "extract 失敗 (exit=$_EXTRACT_EXIT), queuing for retry"
  if [[ "${KRAG_LL_RETRY:-0}" == "1" ]]; then
    exit 1
  fi
  if queue_push "$HOOK_NAME" "ollama" "$TRANSCRIPT_PATH" "$PROJECT_CWD"; then
    log_info "queued for retry (ollama): $TRANSCRIPT_PATH"
  else
    log_error "queue_push failed after extract failure"
  fi
  exit 0
fi

# 結果ファイル確認（extract.sh がミスなしと判断した場合はファイルなし）
# extract.sh が書き込んだファイルを最新のもので特定
_LL_FILE=$(ls -t "${OUTPUT_DIR}/lessons-learned/${DATE}-"*"-${PROJECT}.md" 2>/dev/null | head -1)
if [[ -z "$_LL_FILE" ]] || [[ ! -s "$_LL_FILE" ]]; then
  log_info "no mistake detected, skipping"
  echo "  ℹ lessons-learned: ミスなし、スキップ ($PROJECT)" >&2
  exit 0
fi

log_info "saved: $_LL_FILE"
echo "✓ lessons-learned: ミス検知 → $(basename "$_LL_FILE")" >&2

# knowledge-rag 登録
LLM="$HOME/.local/share/knowledge-rag/venv/bin/llm"
if [[ -x "$LLM" ]]; then
  echo "  → knowledge-rag 登録中..." >&2
  _LL_BASE="${_LL_FILE##*/}"; _LL_BASE="${_LL_BASE%.md}"
  KRAG_REL="lessons-learned/${_LL_BASE}.md"
  {
    echo "add_documentツールを使って次のMarkdownをknowledge-ragに登録してください。"
    echo "filepath: ${KRAG_REL}"
    echo "category: lessons-learned"
    echo "content:"
    cat "$_LL_FILE"
  } | KNOWLEDGE_RAG_DIR="$HOME/.local/share/knowledge-rag" \
    "$LLM" prompt -m "$_DISTILL_MODEL" -T MCP --no-stream \
    >>"$_HOOK_LOG" 2>&1 || true
fi

wait
