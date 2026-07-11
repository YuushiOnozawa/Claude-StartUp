#!/usr/bin/env bash
# lessons-learned-stop: Stop hook
# LLM不使用。Esc割り込み時にトランスクリプトを lessons-learned キューに積む。
# 終了コード方針（カテゴリ B / Issue #51）:
#   exit 0 — 想定内スキップ（短いセッション・重複キュー）、またはキュー追加
#   非ゼロ  — 想定外エラー（set -euo pipefail による自動終了）
# NOTE: core-03.2 SPEC-03.2-05 で改修予定の旧実装（レガシー）。還流は現状記録目的。

set -euo pipefail

HOOK_DIR="$(dirname "$0")"

# shellcheck source=lib/logging.sh
source "${HOOK_DIR}/lib/logging.sh"
# shellcheck source=lib/queue.sh
source "${HOOK_DIR}/lib/queue.sh"

HOOK_NAME="lessons-learned"
MIN_ASST_MESSAGES=3

# stdin から JSON を読む
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
PROJECT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  log_info "no transcript, skipping"
  exit 0
fi

# アシスタントメッセージ数チェック（短いセッションはスキップ）
ASST_COUNT=$(jq -rn '[inputs |
  ((.role // .type // "") | ascii_downcase) as $r |
  select($r == "assistant")
] | length' "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)

if [[ "$ASST_COUNT" -lt "$MIN_ASST_MESSAGES" ]]; then
  log_info "too few assistant messages (${ASST_COUNT} < ${MIN_ASST_MESSAGES}), skipping"
  exit 0
fi

# 同一 transcript_path の重複キューチェック（cwd ではなく transcript_path で判定）
QUEUE_DIR="${QUEUE_BASE_DIR}/${HOOK_NAME}"
if [[ -d "$QUEUE_DIR" ]]; then
  for f in "${QUEUE_DIR}"/*.json; do
    [[ -f "$f" ]] || continue
    item_transcript=$(jq -r '.transcript_path // ""' "$f" 2>/dev/null)
    if [[ "$item_transcript" == "$TRANSCRIPT_PATH" ]]; then
      log_info "queue already has item for this transcript, skipping"
      exit 0
    fi
  done
fi

# キューに積む
if queue_push "$HOOK_NAME" "esc_interrupt" "$TRANSCRIPT_PATH" "$PROJECT_CWD"; then
  log_info "queued: ${TRANSCRIPT_PATH}"
else
  log_error "queue_push failed"
fi

exit 0
