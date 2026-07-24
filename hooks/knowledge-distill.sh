#!/usr/bin/env bash
# knowledge-distill: SessionEnd hook — orchestrator
# Extracts knowledge from session transcript and saves to Obsidian via Ollama.
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
HOOK_NAME="knowledge-distill"

# Ollama 起動確認（スクリプト全体で共有、複数回確認を防ぐ）
_OLLAMA_UP=0
ollama_is_up && _OLLAMA_UP=1 || true

# キュー drain（リトライ実行時はスキップして無限ループを防ぐ）
if [[ "${KRAG_DISTILL_RETRY:-0}" != "1" ]]; then
  _distill_retry_callback() {
    local item_file="$1"
    t=$(jq -e -r '.transcript_path // empty' "$item_file" 2>/dev/null) || { log_error "failed to read transcript_path from $item_file (null or missing)"; return 1; }
    c=$(jq -r '.cwd // ""' "$item_file" 2>/dev/null) || true
    log_info "retrying queued item: $(basename "$t")"
    jq -n --arg transcript_path "$t" --arg cwd "$c" \
      '{"transcript_path":$transcript_path,"cwd":$cwd}' \
      | KRAG_DISTILL_RETRY=1 bash "${_DISTILL_HOOK_DIR}/knowledge-distill.sh"
  }
  _DISTILL_HOOK_DIR="$HOOK_DIR"
  _cnt_pending=$(queue_count "$HOOK_NAME" "pending" 2>/dev/null)
  _cnt_pcloud=$(queue_count "$HOOK_NAME" "pcloud" 2>/dev/null)
  _drain_count=$(( ${_cnt_pending:-0} + ${_cnt_pcloud:-0} ))
  if [[ $_OLLAMA_UP -eq 1 ]]; then
    _cnt_ollama=$(queue_count "$HOOK_NAME" "ollama" 2>/dev/null)
    _drain_count=$(( _drain_count + ${_cnt_ollama:-0} ))
  fi
  if [[ $_drain_count -gt 0 ]]; then
    echo "⏳ knowledge-distill: 保留キュー ${_drain_count} 件をリトライ中..." >&2
  fi
  queue_drain "$HOOK_NAME" "pending" "_distill_retry_callback"
  queue_drain "$HOOK_NAME" "pcloud" "_distill_retry_callback"
  if [[ $_OLLAMA_UP -eq 1 ]]; then
    queue_drain "$HOOK_NAME" "ollama" "_distill_retry_callback"
  fi
fi

# Read SessionEnd JSON from stdin
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  log_info "no transcript, skipping"
  echo "  ℹ knowledge-distill: transcript なし、スキップ" >&2
  exit 0
fi

# CONVERSATION 空チェック（extract.sh でも再抽出するが、ここで早期終了判定のみ）
CONVERSATION=$(jq -rn '
  [inputs |
    ((.role // .type // "") | ascii_downcase) as $r |
    (
      (.message.content // .msg.content // .content // "") |
      if type == "array" then map(select(.type == "text") | .text) | join(" ")
      elif type == "string" then .
      else "" end
    ) as $text |
    if ($r == "human" or $r == "user") and ($text | length) > 0 then
      "User: \($text)"
    elif $r == "assistant" and ($text | length) > 0 then
      "Claude: \($text)"
    else empty end
  ] | join("\n") | .[0:4000]
' "$TRANSCRIPT_PATH" 2>/dev/null)
if [[ -z "$CONVERSATION" ]]; then
  log_info "empty conversation, skipping"
  echo "  ℹ knowledge-distill: 会話内容なし、スキップ" >&2
  exit 0
fi

# Metadata
PROJECT_CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"' 2>/dev/null)
PROJECT=$(basename "$PROJECT_CWD" 2>/dev/null || echo "unknown")
DATE=$(date +%Y-%m-%d)
# TRANSCRIPT_BASE: transcript ファイル名（拡張子除く）を基準にする
# → 初回実行・リトライで同一のファイル名が保証され、raw と distilled が対応する
TRANSCRIPT_BASE="${TRANSCRIPT_PATH##*/}"; TRANSCRIPT_BASE="${TRANSCRIPT_BASE%.*}"
OUTPUT_DIR="$HOME/.local/share/knowledge-rag/documents/sessions"
OUTPUT_FILE="${OUTPUT_DIR}/${DATE}-${TRANSCRIPT_BASE}-${PROJECT}.md"

mkdir -p "$OUTPUT_DIR"

# Raw session log（初回のみ生成 — リトライ時はスキップ）
if [[ "${KRAG_DISTILL_RETRY:-0}" != "1" ]]; then
  bash "${HOOK_DIR}/knowledge-distill-raw.sh" \
    "$TRANSCRIPT_PATH" "$DATE" "$PROJECT" "$TRANSCRIPT_BASE" "$OUTPUT_DIR" || true
fi

# Ollama 起動確認
if [[ $_OLLAMA_UP -eq 0 ]]; then
  log_warn "Ollama not running, queuing for retry"
  if [[ "${KRAG_DISTILL_RETRY:-0}" == "1" ]]; then
    log_warn "retry: ollama not running, handing off to queue_drain dead-letter"
    exit 1
  fi
  echo "  ⏳ knowledge-distill: Ollama 未起動 → 保留 ($PROJECT)" >&2
  if queue_push "$HOOK_NAME" "ollama" "$TRANSCRIPT_PATH" "$PROJECT_CWD"; then
    log_info "queued for retry (ollama): $TRANSCRIPT_PATH"
    queue_notify_send "knowledge-distill" "Ollama 未起動のため distill を保留中 ($PROJECT)"
  else
    log_error "queue_push failed"
  fi
  exit 0
fi

# 使用モデルを解決（優先順: env var > model ファイル > ollama list 最大モデル > qwen2.5:7b）
_KRAG_MODEL_FILE="$HOME/.local/share/knowledge-rag/model"
_DISTILL_MODEL="$(ollama_best_model "$_KRAG_MODEL_FILE")"

# 蒸留実行（knowledge-distill-extract.sh に委譲）
_EXTRACT_EXIT=0
bash "${HOOK_DIR}/knowledge-distill-extract.sh" \
  "$TRANSCRIPT_PATH" "$DATE" "$PROJECT" "$TRANSCRIPT_BASE" "$OUTPUT_DIR" "$_DISTILL_MODEL" \
  || _EXTRACT_EXIT=$?

if [[ $_EXTRACT_EXIT -ne 0 ]]; then
  log_warn "extract 失敗 (exit=$_EXTRACT_EXIT), queuing for retry"
  if [[ "${KRAG_DISTILL_RETRY:-0}" == "1" ]]; then
    log_warn "retry: extract failed, handing off to queue_drain dead-letter"
    exit 1
  fi
  if queue_push "$HOOK_NAME" "ollama" "$TRANSCRIPT_PATH" "$PROJECT_CWD"; then
    log_info "queued for retry (ollama): $TRANSCRIPT_PATH"
    queue_notify_send "knowledge-distill" "Ollama 実行失敗のため distill を保留中 ($PROJECT)"
  else
    log_error "queue_push failed after extract failure"
  fi
  exit 0
fi

# 結果ファイル確認（extract.sh が知識なしと判断した場合は OUTPUT_FILE が存在しない）
if [[ ! -s "$OUTPUT_FILE" ]]; then
  log_info "no knowledge extracted, skipping"
  echo "  ℹ knowledge-distill: 知識なし、スキップ ($PROJECT)" >&2
  exit 0
fi

log_info "saved: $OUTPUT_FILE"
echo "✓ knowledge-distill: セッション保存完了 → $(basename "$OUTPUT_FILE")" >&2

# knowledge-rag 登録（knowledge-distill-register.sh に委譲）
bash "${HOOK_DIR}/knowledge-distill-register.sh" \
  "$OUTPUT_FILE" "$TRANSCRIPT_BASE" "$DATE" "$PROJECT" "$_DISTILL_MODEL"

# 類似セッション検出 → 自動昇格（knowledge-auto-promote.sh が存在する場合のみ）
if [[ -x "${HOOK_DIR}/knowledge-auto-promote.sh" ]]; then
  echo "  → セッション昇格チェック中..." >&2
  "${HOOK_DIR}/knowledge-auto-promote.sh" "$OUTPUT_FILE" >>"$_HOOK_LOG" 2>&1 || true
fi

wait
