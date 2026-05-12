#!/usr/bin/env bash
# check-queue: UserPromptSubmit hook
# キューに未通知の保留アイテムがあれば Claude に通知する（1アイテム1回）
# Exit code policy: always exit 0 — UserPromptSubmit hook must never block user input.

# stdin を消費（UserPromptSubmit は JSON を渡してくるが今回は不使用）
INPUT=$(cat)

HOOK_DIR="$(dirname "$0")"
QUEUE_BASE_DIR="${HOME}/.claude/hooks/queue"

# shellcheck source=lib/queue.sh
source "${HOOK_DIR}/lib/queue.sh" 2>/dev/null || exit 0

HOOK_NAME="knowledge-distill"

# 未通知アイテムがなければ何もしない
queue_notify_needed "$HOOK_NAME" || exit 0

# 未通知アイテムの詳細を収集
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

[[ "$count" -eq 0 ]] && exit 0

# 通知済みマーク（この出力後は再通知しない）
queue_notify_mark "$HOOK_NAME"

# stdout に出力 → Claude の会話コンテキストに注入される
printf '[HOOK] knowledge-distill キューに %d 件の保留があります:\n%b\n' "$count" "$items_output"
printf '原因が解消されたら次のセッション終了時（/clear）に自動リトライされます。\n'
printf '今すぐ原因を調べるか、対応が必要か確認してください。\n'
