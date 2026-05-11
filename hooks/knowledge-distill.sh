#!/usr/bin/env bash
# knowledge-distill: SessionEnd hook
# Extracts knowledge from session transcript and saves to Obsidian via Ollama.

set -euo pipefail

# shellcheck source=lib/logging.sh
source "$(dirname "$0")/lib/logging.sh"

# Read SessionEnd JSON from stdin
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  log_info "no transcript, skipping"
  exit 0
fi

# Extract conversation text from Claude Code JSONL transcript
# Handles both {type: human/assistant} and {role: user/assistant} formats
# Content may be a string or array of content blocks
CONVERSATION=$(jq -rn '
  [inputs |
    ((.role // .type) | ascii_downcase) as $r |
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
  exit 0
fi

# Metadata
PROJECT_CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"' 2>/dev/null)
PROJECT=$(basename "$PROJECT_CWD" 2>/dev/null || echo "unknown")
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H%M%S)
OUTPUT_DIR="$HOME/pcloud/obsidian/sessions"
OUTPUT_FILE="${OUTPUT_DIR}/${DATE}-${TIME}-${PROJECT}.md"

# pCloud マウント確認（マウント管理は systemd サービスの責務）
if ! mountpoint -q "$HOME/pcloud"; then
  log_error "pCloud not mounted at $HOME/pcloud"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Raw session log（LLM不要・Ollama障害時もここまでは実行される）
RAW_DIR="${OUTPUT_DIR}/raw"
RAW_FILE="${RAW_DIR}/${DATE}-${TIME}-${PROJECT}.md"
mkdir -p "$RAW_DIR"

{
  printf -- '---\ndate: %s\nproject: %s\ntags: [session, raw-log]\n---\n\n# セッション記録 %s %s\n\n' \
    "$DATE" "$PROJECT" "$DATE" "$TIME"
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

# Check Ollama is running
if ! curl -sf --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1; then
  log_warn "Ollama not running, skipping"
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

RESULT=$(curl -s --max-time 120 http://localhost:11434/api/generate \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg model "qwen2.5:3b" --arg prompt "$PROMPT" \
    '{"model":$model,"prompt":$prompt,"stream":false}')" \
  | jq -r '.response // ""' 2>/dev/null)

if [[ -z "$RESULT" ]] || [[ "$RESULT" == "記録なし" ]]; then
  log_info "no knowledge extracted, skipping"
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

# knowledge-rag への自動登録（llm + MCP ツール経由）
# KRAG_DISTILL_MODEL: 使用モデル（デフォルト: qwen2.5:3b）
# KRAG_DISTILL_STRICT: 1 のとき失敗でexit 1（Issue #30 ハイスペックモード連動用）
LLM="$HOME/.local/share/knowledge-rag/venv/bin/llm"
if [[ -x "$LLM" ]]; then
  KRAG_MODEL="${KRAG_DISTILL_MODEL:-qwen2.5:3b}"
  KRAG_STRICT="${KRAG_DISTILL_STRICT:-0}"
  KRAG_REL="sessions/${DATE}-${TIME}-${PROJECT}.md"
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
