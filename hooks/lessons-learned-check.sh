#!/usr/bin/env bash
# lessons-learned-check: UserPromptSubmit hook
# Haiku でトランスクリプトを解析し、ミスが検知されたら lessons-learned を knowledge-rag に登録。
# 終了コード方針（カテゴリ A / Issue #51）: 常に exit 0 — ユーザー入力をブロックしない。
# 内部エラーは log_warn で記録し || true で握りつぶす。

HOOK_DIR="$(dirname "$0")"
QUEUE_BASE_DIR="${HOME}/.claude/hooks/queue"

# shellcheck source=lib/logging.sh
source "${HOOK_DIR}/lib/logging.sh" 2>/dev/null || exit 0
# shellcheck source=lib/queue.sh
source "${HOOK_DIR}/lib/queue.sh" 2>/dev/null || exit 0

HOOK_NAME="lessons-learned"
HAIKU_MODEL="claude-haiku-4-5-20251001"
_KRAG_DIR="${HOME}/.local/share/knowledge-rag"
_LLM="${_KRAG_DIR}/venv/bin/llm"
_KRAG_MODEL_FILE="${_KRAG_DIR}/model"
_DISTILL_MODEL="${KRAG_DISTILL_MODEL:-$(grep . "$_KRAG_MODEL_FILE" 2>/dev/null || echo "qwen2.5:3b")}"
_LL_LOG="${HOME}/.claude/hooks/logs/lessons-learned.log"

# stdin 消費（UserPromptSubmit は JSON を渡してくるが本スクリプトでは不使用）
cat > /dev/null

# キュー件数チェック（高速パス）
QUEUE_COUNT=$(queue_count "$HOOK_NAME" 2>/dev/null) || QUEUE_COUNT=0
if [[ "$QUEUE_COUNT" -eq 0 ]]; then
  exit 0
fi

# ANTHROPIC_API_KEY チェック
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  log_warn "ANTHROPIC_API_KEY not set, lessons-learned analysis deferred"
  exit 0
fi

# pCloud マウント確認（書き込み先のため Haiku 呼び出しより前にガード）
if ! mountpoint -q "$HOME/pcloud" 2>/dev/null; then
  log_warn "pCloud not mounted, lessons-learned analysis deferred"
  exit 0
fi

mkdir -p "$HOME/pcloud/obsidian/lessons-learned" || true
mkdir -p "$(dirname "$_LL_LOG")" || true

# コールバック関数: queue_drain から item_file パスを受け取る
_ll_process_item() {
  local item_file="$1"
  local _transcript_path _project_cwd _project _date _time _output_file

  _transcript_path=$(jq -r '.transcript_path // ""' "$item_file" 2>/dev/null) || return 1
  _project_cwd=$(jq -r '.cwd // ""' "$item_file" 2>/dev/null) || return 1
  _project=$(basename "$_project_cwd" 2>/dev/null || echo "unknown")
  _date=$(date +%Y-%m-%d)
  _time=$(date +%H%M%S)
  _output_file="$HOME/pcloud/obsidian/lessons-learned/${_date}-${_time}-${_project}.md"

  # 会話テキスト抽出（knowledge-distill.sh のパターン）
  local _conversation
  _conversation=$(jq -rn '
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
  ' "$_transcript_path" 2>/dev/null) || {
    log_warn "failed to extract conversation from ${_transcript_path}"
    return 1
  }

  if [[ -z "$_conversation" ]]; then
    log_info "empty conversation in ${_transcript_path}, skipping"
    return 0
  fi

  # Haiku でミス分析・ドキュメント生成
  local _prompt
  _prompt="以下の会話でClaudeに明確なミス・失敗・誤動作がありましたか？

判定基準:
- 間違ったコードを生成して修正が必要になった
- 誤った事実・前提で作業が止まった
- ループ・同じミスの繰り返しが発生した

ミスがない場合は「NO_MISTAKE」とだけ出力してください。

ミスがある場合は以下のMarkdownのみ出力してください（前置き・後書き不要）:
---
title: <ミスの要約（1行）>
tags: [lessons-learned]
project: ${_project}
date: ${_date}
---
# 状況
<何をしようとしていたか>

# ミス
<何が起きたか>

# 原因
<なぜ起きたか>

# 解決
<どう対応したか・何が正しかったか>

# 防止策
<CLAUDE.md/skills/hooks で防げるか。具体的な改善案>

[会話]
${_conversation}"

  local _haiku_tmp _curl_exit _new_content
  _haiku_tmp=$(mktemp)
  trap 'rm -f "$_haiku_tmp"' RETURN

  _curl_exit=0
  curl -s --max-time 30 \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    "https://api.anthropic.com/v1/messages" \
    -d "$(jq -n \
      --arg model "$HAIKU_MODEL" \
      --arg content "$_prompt" \
      '{"model":$model,"max_tokens":2048,"messages":[{"role":"user","content":$content}]}')" \
    > "$_haiku_tmp" || _curl_exit=$?

  if [[ $_curl_exit -ne 0 ]]; then
    log_warn "Haiku API call failed (exit=${_curl_exit})"
    return 1
  fi

  _new_content=$(jq -r '.content[0].text // empty' "$_haiku_tmp" 2>/dev/null) || {
    log_warn "failed to parse Haiku response"
    return 1
  }

  if [[ -z "$_new_content" ]]; then
    log_warn "Haiku returned empty content"
    return 1
  fi

  # NO_MISTAKE → 削除して終了
  if [[ "$_new_content" =~ ^NO_MISTAKE ]]; then
    log_info "no mistake detected in ${_transcript_path}"
    return 0
  fi

  # ミス検知: ファイル書き込み
  printf '%s\n' "$_new_content" > "$_output_file" || {
    log_warn "failed to write lessons-learned file: ${_output_file}"
    return 1
  }
  log_info "lessons-learned saved: ${_output_file}"

  # タイトル抽出（通知用）
  local _title
  _title=$(printf '%s' "$_new_content" | grep '^title:' | head -1 | sed 's/^title: *//' | cut -c1-60) \
    || _title="(タイトル不明)"

  # knowledge-rag 登録（Ollama 必須）
  if curl -sf --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1; then
    if [[ -x "$_LLM" ]]; then
      local _krag_rel="lessons-learned/${_date}-${_time}-${_project}.md"
      {
        echo "add_documentツールを使って次のMarkdownをknowledge-ragに登録してください。"
        echo "filepath: ${_krag_rel}"
        echo "category: lessons-learned"
        echo "content:"
        cat "$_output_file"
      } | KNOWLEDGE_RAG_DIR="$_KRAG_DIR" \
        "$_LLM" prompt -m "$_DISTILL_MODEL" -T MCP --no-stream >> "$_LL_LOG" 2>&1 \
        && log_info "registered to knowledge-rag: ${_krag_rel}" \
        || log_warn "knowledge-rag registration failed (file saved to pCloud)"
    else
      log_warn "llm CLI not found: ${_LLM} (file saved to pCloud)"
    fi
  else
    log_warn "Ollama not running, knowledge-rag registration skipped (file saved to pCloud)"
  fi

  # stdout 通知（→ Claude のコンテキストに注入）
  printf '[HOOK] lessons-learned を保存しました: %s\n' "$_title"

  return 0
}

# キューを処理
queue_drain "$HOOK_NAME" "esc_interrupt" _ll_process_item || true
