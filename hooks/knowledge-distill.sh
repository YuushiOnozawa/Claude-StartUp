#!/usr/bin/env bash
# knowledge-distill: SessionEnd hook
# Extracts knowledge from session transcript and saves to Obsidian via Ollama.

set -euo pipefail

# Read SessionEnd JSON from stdin
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
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
  exit 0
fi

# Metadata
PROJECT_CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"' 2>/dev/null)
PROJECT=$(basename "$PROJECT_CWD" 2>/dev/null || echo "unknown")
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H%M%S)
OUTPUT_DIR="$HOME/pcloud/obsidian/sessions"
OUTPUT_FILE="${OUTPUT_DIR}/${DATE}-${TIME}-${PROJECT}.md"

mkdir -p "$OUTPUT_DIR"

# Check Ollama is running
if ! curl -sf --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1; then
  echo "knowledge-distill: Ollama not running, skipping" >&2
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
