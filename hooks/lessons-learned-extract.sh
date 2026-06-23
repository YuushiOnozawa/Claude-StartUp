#!/usr/bin/env bash
# lessons-learned-extract: ミス検知 + result ファイル生成
# 引数: $1=TRANSCRIPT_PATH $2=DATE $3=PROJECT $4=OUTPUT_DIR $5=DISTILL_MODEL
set -euo pipefail

HOOK_DIR="$(dirname "$0")"
# shellcheck source=lib/logging.sh
source "${HOOK_DIR}/lib/logging.sh"
_HOOK_NAME="lessons-learned-distill"  # ログファイルを orchestrator と統一
_HOOK_LOG="${HOOK_LOG_DIR}/${_HOOK_NAME}.log"

TRANSCRIPT_PATH="$1"
DATE="$2"
PROJECT="$3"
OUTPUT_DIR="$4"
DISTILL_MODEL="$5"

TIME=$(date +%H%M%S)
OUTPUT_FILE="${OUTPUT_DIR}/lessons-learned/${DATE}-${TIME}-${PROJECT}.md"
mkdir -p "$(dirname "$OUTPUT_FILE")"

# CONVERSATION 抽出（TRANSCRIPT_PATH から jq で再抽出）
CONVERSATION=$(jq -rn '
  [inputs |
    ((.role // .type // "") | ascii_downcase) as $r |
    (
      (.msg.content // .content // "") |
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
  exit 0
fi

PROMPT="以下の会話でClaudeに明確なミス・失敗・誤動作がありましたか？

判定基準:
- 間違ったコードを生成して修正が必要になった
- 誤った事実・前提で作業が止まった
- ループ・同じミスの繰り返しが発生した

ミスがない場合は「記録なし」とだけ出力してください。

ミスがある場合は以下のMarkdown形式のみ出力（前置き・後書き不要）:
---
title: <ミスの要約（1行）>
tags: [lessons-learned]
project: ${PROJECT}
date: ${DATE}
---
# 状況
<何をしようとしていたか>
# ミス
<何が起きたか>
# 原因
<なぜ起きたか>
# 解決
<どう対応したか>
# 防止策
<CLAUDE.md/skills/hooks で防げるか>

[会話]
${CONVERSATION}"

echo "⏳ lessons-learned: Ollama 推論中 (${DISTILL_MODEL})..." >&2

_OLLAMA_RUN="${HOOK_DIR}/../scripts/ollama-run.sh"
_OLLAMA_EXIT=0
RESULT="$(printf '%s\n' "$PROMPT" | bash "$_OLLAMA_RUN" "$DISTILL_MODEL")" || _OLLAMA_EXIT=$?

if [[ $_OLLAMA_EXIT -ne 0 ]]; then
  log_warn "Ollama 実行失敗 (exit=$_OLLAMA_EXIT)"
  exit 1
fi

echo "  → 推論完了" >&2

if [[ -z "$RESULT" ]] || [[ "$RESULT" =~ 記録なし ]]; then
  log_info "no mistake detected, skipping"
  exit 0
fi

printf '%s\n' "$RESULT" > "$OUTPUT_FILE"
log_info "saved: $OUTPUT_FILE"
