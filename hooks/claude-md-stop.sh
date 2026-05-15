#!/usr/bin/env bash
# claude-md-stop: Stop hook
# LLM不使用。プロジェクト CLAUDE.md が 200行超なら claude-md-lifecycle キューに積む。
# 終了コード方針（カテゴリ B / Issue #51）:
#   exit 0 — 想定内スキップ（CLAUDE.md なし・行数以内・重複キュー）、またはキュー追加
#   非ゼロ  — 想定外エラー（set -euo pipefail による自動終了）

set -euo pipefail

HOOK_DIR="$(dirname "$0")"

# shellcheck source=lib/logging.sh
source "${HOOK_DIR}/lib/logging.sh"
# shellcheck source=lib/queue.sh
source "${HOOK_DIR}/lib/queue.sh"

HOOK_NAME="claude-md-lifecycle"
LINE_LIMIT=200

# stdin から JSON を読む
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
PROJECT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

if [[ -z "$TRANSCRIPT_PATH" ]] || [[ -z "$PROJECT_CWD" ]]; then
  log_info "no transcript or cwd, skipping"
  exit 0
fi

# プロジェクト CLAUDE.md を探す（グローバルは対象外）
CLAUDE_MD="${PROJECT_CWD}/CLAUDE.md"
if [[ ! -f "$CLAUDE_MD" ]]; then
  CLAUDE_MD="${PROJECT_CWD}/.claude/CLAUDE.md"
fi
if [[ ! -f "$CLAUDE_MD" ]]; then
  log_info "no project CLAUDE.md found in ${PROJECT_CWD}, skipping"
  exit 0
fi

# 行数チェック
LINE_COUNT=$(wc -l < "$CLAUDE_MD")
if [[ "$LINE_COUNT" -le "$LINE_LIMIT" ]]; then
  log_info "CLAUDE.md lines=${LINE_COUNT} <= ${LINE_LIMIT}, skipping"
  exit 0
fi

# 同一 cwd のキューアイテムが既に存在すれば重複積みしない
QUEUE_DIR="${QUEUE_BASE_DIR}/${HOOK_NAME}"
if [[ -d "$QUEUE_DIR" ]]; then
  for f in "${QUEUE_DIR}"/*.json; do
    [[ -f "$f" ]] || continue
    item_cwd=$(jq -r '.cwd // ""' "$f" 2>/dev/null)
    if [[ "$item_cwd" == "$PROJECT_CWD" ]]; then
      log_info "queue already has item for ${PROJECT_CWD}, skipping"
      exit 0
    fi
  done
fi

# キューに積む
if queue_push "$HOOK_NAME" "lines_${LINE_COUNT}" "$TRANSCRIPT_PATH" "$PROJECT_CWD"; then
  log_info "queued: CLAUDE.md lines=${LINE_COUNT} > ${LINE_LIMIT} in ${PROJECT_CWD}"
else
  log_error "queue_push failed"
fi

exit 0
