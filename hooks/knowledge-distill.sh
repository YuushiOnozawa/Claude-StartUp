#!/usr/bin/env bash
# knowledge-distill: SessionEnd hook
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

# Ollama 起動確認（スクリプト全体で共有、複数回 curl 実行を防ぐ）
_OLLAMA_UP=0
curl -sf --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1 && _OLLAMA_UP=1

# キューdrain（リトライ実行時はスキップして無限ループを防ぐ）
if [[ "${KRAG_DISTILL_RETRY:-0}" != "1" ]] && mountpoint -q "$HOME/pcloud"; then
  _distill_retry_callback() {
    local item_file="$1"
    local t c
    t=$(jq -e -r '.transcript_path // empty' "$item_file" 2>/dev/null) || { log_error "failed to read transcript_path from $item_file (null or missing)"; return 1; }
    c=$(jq -r '.cwd // ""' "$item_file" 2>/dev/null) || true  # cwd はオプション（// "" で空文字列フォールバック済み）
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

# Extract conversation text from Claude Code JSONL transcript
# Handles both {type: human/assistant} and {role: user/assistant} formats
# Content may be a string or array of content blocks
CONVERSATION=$(jq -rn '
  [inputs |
    ((.role // .type // "") | ascii_downcase) as $r |
    (
      (.message.content // .content // "") |
      if type == "array" then map(select(.type == "text") | .text) | join(" ")
      elif type == "string" then .
      else ""
      end
    ) as $text |
    if ($r == "human" or $r == "user") and ($text | length) > 0 then
      "User: \($text)"
    elif $r == "assistant" and ($text | length) > 0 then
      "Claude: \($text)"
    else empty
    end
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
TRANSCRIPT_BASE=$(basename "$TRANSCRIPT_PATH" | sed 's/\.[^.]*$//')
OUTPUT_DIR="$HOME/pcloud/obsidian/sessions"
OUTPUT_FILE="${OUTPUT_DIR}/${DATE}-${TRANSCRIPT_BASE}-${PROJECT}.md"

# pCloud マウント確認（マウント管理は systemd サービスの責務）
if ! mountpoint -q "$HOME/pcloud"; then
  log_error "pCloud not mounted at $HOME/pcloud"
  echo "  ⏳ knowledge-distill: pCloud 未マウント → 保留 ($PROJECT)" >&2
  if queue_push "$HOOK_NAME" "pcloud" "$TRANSCRIPT_PATH" "$PROJECT_CWD"; then
    log_info "queued for retry: $TRANSCRIPT_PATH"
    queue_notify_send "knowledge-distill" "pCloud 未マウントのため保留中 ($PROJECT)"
  else
    log_error "queue_push failed"
  fi
  exit 0
fi

mkdir -p "$OUTPUT_DIR"

# Raw session log（初回のみ生成 — リトライ時はスキップ）
# リトライは Ollama 推論のみ再実行すればよく、raw は初回 SessionEnd で既に生成済みのため
if [[ "${KRAG_DISTILL_RETRY:-0}" != "1" ]]; then
  RAW_DIR="${OUTPUT_DIR}/raw"
  RAW_FILE="${RAW_DIR}/${DATE}-${TRANSCRIPT_BASE}-${PROJECT}.md"
  mkdir -p "$RAW_DIR"

  {
    printf -- '---\ndate: %s\nproject: %s\ntags: [session, raw-log]\n---\n\n# セッション記録 %s %s\n\n' \
      "$DATE" "$PROJECT" "$DATE" "$TRANSCRIPT_BASE"
    jq -rn '
      [inputs |
        ((.role // .type // "") | ascii_downcase) as $r |
        (
          (.message.content // .content // "") |
          if type == "array" then
            map(
              if .type == "text" then .text
              elif .type == "tool_use" then
                "**Tool**: " + .name + " \u2192 " +
                (
                  (.input // {}) |
                  (.url // .query // .command // .file_path // .pattern //
                   (to_entries[0].value // "")) |
                  if type == "string" then .[0:80] else tostring[0:80] end
                )
              else empty
              end
            ) | join("\n")
          elif type == "string" then .
          else ""
          end
        ) as $body |
        if ($body | length) > 0 then
          if ($r == "human" or $r == "user") then "## User\n\($body)"
          elif $r == "assistant" then "## Claude\n\($body)"
          else empty
          end
        else empty
        end
      ] | join("\n\n---\n\n")
    ' "$TRANSCRIPT_PATH" 2>/dev/null
  } > "$RAW_FILE" \
    && log_info "raw log saved: $RAW_FILE" \
    || { log_warn "raw log generation failed (non-fatal)"; rm -f "$RAW_FILE"; }
fi

# Check Ollama is running
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

PROMPT="次の会話から重要な知識を日本語で抽出してください。

出力形式（Markdown）：
## 判明した事実・結論
- 箇条書き

## 調べた情報源・URL
- 名称と確認日（${DATE}）

## 下した判断とその理由
- 判断内容と理由

## 次回確認が必要な事項
- 古くなりそうな情報や未確認事項

重要な知識が含まれない場合は「記録なし」とだけ出力してください。

会話：
${CONVERSATION}"

# 使用モデルを解決（優先順: env var > model ファイル > ollama list 最大モデル > qwen2.5:7b）
_KRAG_MODEL_FILE="$HOME/.local/share/knowledge-rag/model"
_DISTILL_MODEL="$(ollama_best_model "$_KRAG_MODEL_FILE")"

echo "⏳ knowledge-distill: Ollama 推論中 ($_DISTILL_MODEL, 最大 120s)..." >&2
_OLLAMA_TMP=$(mktemp)
trap 'rm -f "$_OLLAMA_TMP"' EXIT
_CURL_EXIT=0
curl -s --max-time 120 http://localhost:11434/api/generate \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg model "$_DISTILL_MODEL" --arg prompt "$PROMPT" \
    '{"model":$model,"prompt":$prompt,"stream":false}')" \
  > "$_OLLAMA_TMP" || _CURL_EXIT=$?

if [[ $_CURL_EXIT -ne 0 ]]; then
  log_warn "Ollama API failed (exit=$_CURL_EXIT), queuing for retry"
  if [[ "${KRAG_DISTILL_RETRY:-0}" == "1" ]]; then
    log_warn "retry: ollama API failed, handing off to queue_drain dead-letter"
    exit 1
  fi
  if queue_push "$HOOK_NAME" "ollama" "$TRANSCRIPT_PATH" "$PROJECT_CWD"; then
    log_info "queued for retry (ollama-timeout): $TRANSCRIPT_PATH"
    queue_notify_send "knowledge-distill" "Ollama タイムアウトのため distill を保留中 ($PROJECT)"
  else
    log_error "queue_push failed after ollama timeout"
  fi
  exit 0
fi

_JQ_EXIT=0
RESULT=$(jq -r '.response // ""' "$_OLLAMA_TMP" 2>/dev/null) || _JQ_EXIT=$?

if [[ $_JQ_EXIT -ne 0 ]]; then
  log_warn "Ollama response parse failed (exit=$_JQ_EXIT), queuing for retry"
  if [[ "${KRAG_DISTILL_RETRY:-0}" == "1" ]]; then
    log_warn "retry: ollama response parse failed, handing off to queue_drain dead-letter"
    exit 1
  fi
  if queue_push "$HOOK_NAME" "ollama" "$TRANSCRIPT_PATH" "$PROJECT_CWD"; then
    log_info "queued for retry (ollama-json): $TRANSCRIPT_PATH"
    queue_notify_send "knowledge-distill" "Ollama JSON パースエラーのため distill を保留中 ($PROJECT)"
  else
    log_error "queue_push failed after ollama json parse error"
  fi
  exit 0
fi

echo "  → 推論完了" >&2
if [[ -z "$RESULT" ]] || [[ "$RESULT" == "記録なし" ]]; then
  log_info "no knowledge extracted, skipping"
  echo "  ℹ knowledge-distill: 知識なし、スキップ ($PROJECT)" >&2
  exit 0
fi

cat > "$OUTPUT_FILE" <<EOF
---
date: ${DATE}
project: ${PROJECT}
tags: [session, auto-distilled]
---

# セッション記録 ${DATE} ${TIME}

${RESULT}
EOF

log_info "saved: $OUTPUT_FILE"
echo "✓ knowledge-distill: セッション保存完了 → $(basename "$OUTPUT_FILE")" >&2

# knowledge-rag への自動登録（llm + MCP ツール経由）
# KRAG_DISTILL_MODEL: 使用モデル（env var > ~/.local/share/knowledge-rag/model > ollama 最大モデル > qwen2.5:7b）
# KRAG_DISTILL_STRICT: 1 のとき失敗でexit 1（Issue #30 ハイスペックモード連動用）
LLM="$HOME/.local/share/knowledge-rag/venv/bin/llm"
if [[ -x "$LLM" ]]; then
  echo "  → knowledge-rag 登録中..." >&2
  KRAG_MODEL="$_DISTILL_MODEL"
  KRAG_STRICT="${KRAG_DISTILL_STRICT:-0}"
  KRAG_REL="sessions/${DATE}-${TRANSCRIPT_BASE}-${PROJECT}.md"
  KRAG_LOG="$_HOOK_LOG"

  {
    echo "add_documentツールを使って次のMarkdownをknowledge-ragに登録してください。"
    echo "filepath: ${KRAG_REL}"
    echo "category: sessions"
    echo "content:"
    cat "$OUTPUT_FILE"
  } | KNOWLEDGE_RAG_DIR="$HOME/.local/share/knowledge-rag" \
    "$LLM" prompt -m "$KRAG_MODEL" -T MCP --no-stream \
    >>"$KRAG_LOG" 2>&1 \
    || [[ "$KRAG_STRICT" != "1" ]]
fi

# 類似セッション検出 → 自動昇格（knowledge-auto-promote.sh が存在する場合のみ）
if [[ -x "${HOOK_DIR}/knowledge-auto-promote.sh" ]]; then
  echo "  → セッション昇格チェック中..." >&2
  "${HOOK_DIR}/knowledge-auto-promote.sh" "$OUTPUT_FILE" >>"$_HOOK_LOG" 2>&1 || true
fi
wait  # tee プロセス（2> >(tee -a ...) による非同期バックグラウンド）の完了を待つ
