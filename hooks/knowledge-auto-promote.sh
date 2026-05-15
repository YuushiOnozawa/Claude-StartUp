#!/usr/bin/env bash
# knowledge-auto-promote: 類似セッション検出 → knowledge/ へ自動昇格
# knowledge-distill.sh 末尾から呼び出される（SessionEnd フック直列処理の一部）
# カテゴリ B: set -euo pipefail 使用、想定内スキップは exit 0

set -euo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/logging.sh
source "${HOOK_DIR}/lib/logging.sh"

SESSION_FILE="${1:-}"
[[ -z "$SESSION_FILE" ]] && { log_info "引数なし、スキップ"; exit 0; }
[[ -f "$SESSION_FILE" ]] || { log_info "セッションファイル未存在: $SESSION_FILE"; exit 0; }

KNOWLEDGE_DIR="$HOME/pcloud/obsidian/knowledge"
LLM="$HOME/.local/share/knowledge-rag/venv/bin/llm"
NOTIFY_FILE="$HOME/.claude/hooks/promote-notifications.jsonl"
_MODEL_FILE="$HOME/.local/share/knowledge-rag/model"
_MODEL="$(grep . "$_MODEL_FILE" 2>/dev/null || echo "qwen2.5:3b")"

# pCloud マウント確認
if ! mountpoint -q "$HOME/pcloud" 2>/dev/null; then
  log_info "pCloud 未マウント、スキップ"
  exit 0
fi

# LLM バイナリ確認
if [[ ! -x "$LLM" ]]; then
  log_info "LLM バイナリなし: $LLM"
  exit 0
fi

# 類似セッション検索（llm + MCP）
# 現セッションファイル名を除いて category:sessions で類似ドキュメントを検索する
SESSION_BASENAME="$(basename "$SESSION_FILE")"
QUERY="$(head -80 "$SESSION_FILE" 2>/dev/null || true)"
if [[ -z "$QUERY" ]]; then
  log_info "セッション内容が空、スキップ"
  exit 0
fi

log_info "類似セッション検索: $SESSION_BASENAME"
SEARCH_RAW="$(echo "search_knowledgeツールを使って category='sessions' で以下のテキストに類似するドキュメントを検索してください。ファイル名が '${SESSION_BASENAME}' のものは除いてください。score 0.7 以上のものがあればそのfilepathを1行で返してください。なければ 'NONE' と返してください。

${QUERY}" \
  | KNOWLEDGE_RAG_DIR="$HOME/.local/share/knowledge-rag" \
    "$LLM" prompt -m "$_MODEL" -T MCP --no-stream 2>>"$_HOOK_LOG" \
  || true)"

# 出力検証: "sessions/" を含む場合のみ類似あり（LLM ゴミ出力対策）
if ! echo "$SEARCH_RAW" | grep -q 'sessions/'; then
  log_info "類似セッションなし（出力: ${SEARCH_RAW:0:100}）"
  exit 0
fi

SIMILAR_PATH="$(echo "$SEARCH_RAW" | grep -o 'sessions/.*\.md' | head -1)"
log_info "類似セッション発見: $SIMILAR_PATH"

# 昇格先パス確認
DEST="$KNOWLEDGE_DIR/$SESSION_BASENAME"
if [[ -f "$DEST" ]]; then
  log_info "昇格済み: $DEST"
  exit 0
fi

# knowledge/ にコピー
mkdir -p "$KNOWLEDGE_DIR"
cp "$SESSION_FILE" "$DEST" || { log_error "cp 失敗: $SESSION_FILE → $DEST"; exit 1; }
log_info "knowledge/ にコピー: $DEST"

# knowledge-rag への登録（category: knowledge）
KRAG_REL="knowledge/$SESSION_BASENAME"
{
  echo "add_documentツールを使って次のMarkdownをknowledge-ragに登録してください。"
  echo "filepath: ${KRAG_REL}"
  echo "category: knowledge"
  echo "content:"
  cat "$DEST"
} | KNOWLEDGE_RAG_DIR="$HOME/.local/share/knowledge-rag" \
  "$LLM" prompt -m "$_MODEL" -T MCP --no-stream >>"$_HOOK_LOG" 2>&1 \
  || log_warn "knowledge-rag 登録失敗（ファイルコピーは完了）"

# 通知の原子書き込み（tmp + mv で競合を防ぐ）
mkdir -p "$(dirname "$NOTIFY_FILE")"
_TMP="$(mktemp "${NOTIFY_FILE}.XXXXXX")"
trap 'rm -f "$_TMP"' EXIT
jq -n --arg ts "$(date +%Y%m%d-%H%M%S)" --arg file "${SESSION_BASENAME}" --arg sim "${SIMILAR_PATH}" \
  '{"ts":$ts,"file":$file,"similar":$sim}' > "$_TMP"
cat "$NOTIFY_FILE" >> "$_TMP" 2>/dev/null || true
mv "$_TMP" "$NOTIFY_FILE"

log_info "auto-promote 完了: ${KRAG_REL}（類似: ${SIMILAR_PATH}）"
