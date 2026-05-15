#!/usr/bin/env bash
# check-queue: UserPromptSubmit hook（通知ディスパッチャー）
# 1. knowledge-distill retry キューの未通知アイテムを通知する
# 2. 自動昇格通知（promote-notifications.jsonl）を表示する
# 終了コード方針（カテゴリ A）: 常に exit 0 — UserPromptSubmit フックはユーザー入力をブロックしない

# stdin を消費（UserPromptSubmit は JSON を渡してくるが今回は不使用）
INPUT=$(cat)

HOOK_DIR="$(dirname "$0")"
QUEUE_BASE_DIR="${HOME}/.claude/hooks/queue"

# shellcheck source=lib/queue.sh
source "${HOOK_DIR}/lib/queue.sh" 2>/dev/null || exit 0

HOOK_NAME="knowledge-distill"

# ─── 1. knowledge-distill retry キュー通知 ───────────────────────────────────
if queue_notify_needed "$HOOK_NAME"; then
  items_output=""
  count=0
  queue_dir="${QUEUE_BASE_DIR}/${HOOK_NAME}"

  for f in "${queue_dir}"/*.json; do
    [[ -f "$f" ]] || continue
    flag="${f%.json}.notified"
    [[ -f "$flag" ]] && continue  # 通知済みはスキップ

    reason=$(jq -r '.reason // "unknown"' "$f" 2>/dev/null)
    cwd=$(jq -r '.cwd // ""' "$f" 2>/dev/null)
    project=$(basename "$cwd" 2>/dev/null || echo "unknown")
    ts=$(basename "$f" .json)
    retry=$(jq -r '.retry_count // 0' "$f" 2>/dev/null)

    case "$reason" in
      pcloud) reason_ja="pCloud 未マウント" ;;
      ollama) reason_ja="Ollama 未起動" ;;
      *)      reason_ja="$reason" ;;
    esac

    items_output="${items_output}  - [${ts}] project: ${project}, 原因: ${reason_ja}, retry: ${retry}/3\n"
    ((count++)) || true
  done

  if [[ "$count" -gt 0 ]]; then
    # 通知済みマーク（この出力後は再通知しない）
    queue_notify_mark "$HOOK_NAME"

    # stdout に出力 → Claude の会話コンテキストに注入される
    printf '[HOOK] knowledge-distill キューに %d 件の保留があります:\n%b\n' "$count" "$items_output"
    printf '原因が解消されたら次のセッション終了時（/clear）に自動リトライされます。\n'
    printf '今すぐ原因を調べるか、対応が必要か確認してください。\n'
  fi
fi

# ─── 2. 自動昇格通知 ─────────────────────────────────────────────────────────
{
  _PROMOTE_NOTIFY="${HOME}/.claude/hooks/promote-notifications.jsonl"
  if [[ -f "$_PROMOTE_NOTIFY" ]] && [[ -s "$_PROMOTE_NOTIFY" ]]; then
    _pc=$(wc -l < "$_PROMOTE_NOTIFY" 2>/dev/null || echo 0)
    printf '[PROMOTE] %d件のセッションを knowledge/ に自動昇格しました:\n' "$_pc"
    while IFS= read -r _line; do
      _fname=$(echo "$_line" | jq -r '.file // "?"' 2>/dev/null || echo "?")
      _sim=$(echo "$_line" | jq -r '.similar // "?"' 2>/dev/null || echo "?")
      printf '  - %s（類似: %s）\n' "$_fname" "$_sim"
    done < "$_PROMOTE_NOTIFY"
    rm -f "$_PROMOTE_NOTIFY"
  fi
} || true
