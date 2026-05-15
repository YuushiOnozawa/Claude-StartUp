#!/usr/bin/env bash
# claude-md-check: UserPromptSubmit hook
# CLAUDE.md 行数チェック + キューがあれば Haiku で自動整理・適用。
# 終了コード方針（カテゴリ A / Issue #51）: 常に exit 0 — ユーザー入力をブロックしない。
# 内部エラーは log_warn で記録し || true で握りつぶす。

HOOK_DIR="$(dirname "$0")"
QUEUE_BASE_DIR="${HOME}/.claude/hooks/queue"

# shellcheck source=lib/logging.sh
source "${HOOK_DIR}/lib/logging.sh" 2>/dev/null || exit 0
# shellcheck source=lib/queue.sh
source "${HOOK_DIR}/lib/queue.sh" 2>/dev/null || exit 0

HOOK_NAME="claude-md-lifecycle"
LINE_LIMIT=200
HAIKU_MODEL="claude-haiku-4-5-20251001"
QUEUE_DIR="${QUEUE_BASE_DIR}/${HOOK_NAME}"

# stdin を消費（UserPromptSubmit は JSON を渡してくる）
INPUT=$(cat)
PROJECT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

if [[ -z "$PROJECT_CWD" ]]; then
  exit 0
fi

# プロジェクト CLAUDE.md を探す（グローバルは対象外）
CLAUDE_MD="${PROJECT_CWD}/CLAUDE.md"
if [[ ! -f "$CLAUDE_MD" ]]; then
  CLAUDE_MD="${PROJECT_CWD}/.claude/CLAUDE.md"
fi

# キュー件数チェック
QUEUE_COUNT=$(queue_count "$HOOK_NAME" 2>/dev/null) || QUEUE_COUNT=0

# キューがなければ行数警告のみ
if [[ "$QUEUE_COUNT" -eq 0 ]]; then
  if [[ -f "$CLAUDE_MD" ]]; then
    LINE_COUNT=$(wc -l < "$CLAUDE_MD")
    if [[ "$LINE_COUNT" -gt "$LINE_LIMIT" ]]; then
      printf '[HOOK] CLAUDE.md が %d 行（上限 %d 行）です。整理を検討してください。\n' \
        "$LINE_COUNT" "$LINE_LIMIT"
    fi
  fi
  exit 0
fi

# CLAUDE.md が見つからなければキューを消してスキップ
if [[ ! -f "$CLAUDE_MD" ]]; then
  log_warn "queue has ${QUEUE_COUNT} items but no project CLAUDE.md found in ${PROJECT_CWD}"
  for f in "${QUEUE_DIR}"/*.json; do
    [[ -f "$f" ]] || continue
    item_cwd=$(jq -r '.cwd // ""' "$f" 2>/dev/null)
    [[ "$item_cwd" == "$PROJECT_CWD" ]] || continue
    rm -f "$f" "${f%.json}.notified" 2>/dev/null || true
  done
  exit 0
fi

ORIG_LINE_COUNT=$(wc -l < "$CLAUDE_MD")

# このプロジェクト向けのキューアイテムがあるか確認
HAS_ITEM=0
for f in "${QUEUE_DIR}"/*.json; do
  [[ -f "$f" ]] || continue
  item_cwd=$(jq -r '.cwd // ""' "$f" 2>/dev/null)
  if [[ "$item_cwd" == "$PROJECT_CWD" ]]; then
    HAS_ITEM=1
    break
  fi
done

if [[ "$HAS_ITEM" -eq 0 ]]; then
  exit 0
fi

# ANTHROPIC_API_KEY チェック
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  log_warn "ANTHROPIC_API_KEY not set, skipping Haiku analysis"
  exit 0
fi

# CLAUDE.md 内容を読む
CLAUDE_MD_CONTENT=$(cat "$CLAUDE_MD") || { log_warn "failed to read CLAUDE.md"; exit 0; }

PROMPT="以下の CLAUDE.md が ${ORIG_LINE_COUNT} 行です（上限 ${LINE_LIMIT} 行）。

冗長・矛盾・古くなったルールを削除・統合して、${LINE_LIMIT} 行以内に収めた新しい CLAUDE.md を出力してください。

ルール:
- 出力は CLAUDE.md の中身のみ（前置き・後書き・説明文は不要）
- Markdown 構造（見出し・箇条書き）を維持する
- 重要なルールは必ず残す
- 行数が上限以内なら変更不要（そのまま出力）

[現在の CLAUDE.md]
${CLAUDE_MD_CONTENT}"

# Haiku API 呼び出し
_HAIKU_TMP=$(mktemp)
trap 'rm -f "$_HAIKU_TMP"' EXIT

_CURL_EXIT=0
curl -s --max-time 30 \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  "https://api.anthropic.com/v1/messages" \
  -d "$(jq -n \
    --arg model "$HAIKU_MODEL" \
    --arg content "$PROMPT" \
    '{"model":$model,"max_tokens":4096,"messages":[{"role":"user","content":$content}]}')" \
  > "$_HAIKU_TMP" || _CURL_EXIT=$?

if [[ $_CURL_EXIT -ne 0 ]]; then
  log_warn "Haiku API call failed (exit=${_CURL_EXIT})"
  exit 0
fi

# レスポンス検証
NEW_CONTENT=$(jq -r '.content[0].text // empty' "$_HAIKU_TMP" 2>/dev/null) || {
  log_warn "failed to parse Haiku response"
  exit 0
}

if [[ -z "$NEW_CONTENT" ]]; then
  log_warn "Haiku returned empty content"
  exit 0
fi

NEW_LINE_COUNT=$(printf '%s\n' "$NEW_CONTENT" | wc -l)

# サニティチェック: 元より大幅に増えていたらスキップ
if [[ "$NEW_LINE_COUNT" -gt $((ORIG_LINE_COUNT + 50)) ]]; then
  log_warn "Haiku response too long (${NEW_LINE_COUNT} lines > original ${ORIG_LINE_COUNT} + 50), skipping"
  exit 0
fi

# CLAUDE.md に書き込み
printf '%s\n' "$NEW_CONTENT" > "$CLAUDE_MD" || { log_warn "failed to write CLAUDE.md"; exit 0; }

log_info "CLAUDE.md updated: ${ORIG_LINE_COUNT} -> ${NEW_LINE_COUNT} lines in ${PROJECT_CWD}"

# このプロジェクトのキューアイテムを削除
for f in "${QUEUE_DIR}"/*.json; do
  [[ -f "$f" ]] || continue
  item_cwd=$(jq -r '.cwd // ""' "$f" 2>/dev/null)
  [[ "$item_cwd" == "$PROJECT_CWD" ]] || continue
  rm -f "$f" "${f%.json}.notified" 2>/dev/null || true
done

# 通知（stdout → Claude のコンテキストに注入）
printf '[HOOK] CLAUDE.md を自動整理しました（%d行 → %d行）\n' "$ORIG_LINE_COUNT" "$NEW_LINE_COUNT"
printf 'git diff %s で確認、git checkout %s で revert できます。\n' "$CLAUDE_MD" "$CLAUDE_MD"
