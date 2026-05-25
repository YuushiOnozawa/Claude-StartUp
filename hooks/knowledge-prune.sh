#!/usr/bin/env bash
# knowledge-prune: SessionEnd hook (bash-only, Issue #92)
# TTL 超過ファイルを archive/ に mv する。
# 次回 MCP サーバー起動時にインクリメンタルインデックスが orphan を自動削除。

set -euo pipefail
# 終了コード方針（カテゴリ B / Issue #51）:
#   exit 0 — 想定内スキップ（pCloud 未マウント→キュー後）
#   非ゼロ  — 想定外エラー（set -euo pipefail による自動終了）

HOOK_DIR="$(dirname "$0")"

# shellcheck source=lib/logging.sh
source "${HOOK_DIR}/lib/logging.sh"
# shellcheck source=lib/queue.sh
source "${HOOK_DIR}/lib/queue.sh"

HOOK_NAME="knowledge-prune"
DOCS_DIR="$HOME/pcloud/obsidian"
ARCHIVE_DIR="$HOME/pcloud/obsidian/archive"

# カテゴリ別 TTL（日数）。-1 は永続保持。
declare -A CATEGORY_TTL=(
  [sessions]=30
  [knowledge]=365
  [investigations]=180
  [lessons-learned]=-1
  [general]=90
)

# キュードレイン（リトライ実行時はスキップして無限ループを防ぐ）
if [[ "${KRAG_PRUNE_RETRY:-0}" != "1" ]] && mountpoint -q "$HOME/pcloud"; then
  _prune_retry_callback() {
    log_info "retrying queued prune"
    KRAG_PRUNE_RETRY=1 bash "${_PRUNE_HOOK_DIR}/knowledge-prune.sh"
  }
  _PRUNE_HOOK_DIR="$(cd "$HOOK_DIR" && pwd)"
  queue_drain "$HOOK_NAME" "pcloud" "_prune_retry_callback"
fi

# pCloud マウント確認 → 未マウントならキューに積んで終了
if ! mountpoint -q "$HOME/pcloud"; then
  log_info "pCloud not mounted, queuing"
  queue_push "$HOOK_NAME" "pcloud" "" ""
  exit 0
fi

if [[ ! -d "$DOCS_DIR" ]]; then
  log_info "documents dir not found: $DOCS_DIR, skipping"
  exit 0
fi

log_info "starting knowledge pruning (bash-only)"

DATE_PREFIX=$(date -u +%Y%m%d)
PRUNED=0
ERRORS=0

for category in "${!CATEGORY_TTL[@]}"; do
  ttl="${CATEGORY_TTL[$category]}"
  [[ "$ttl" -eq -1 ]] && continue

  cat_dir="${DOCS_DIR}/${category}"
  [[ ! -d "$cat_dir" ]] && continue

  archive_cat="${ARCHIVE_DIR}/${category}"
  mkdir -p "$archive_cat"

  while IFS= read -r -d '' filepath; do
    filename=$(basename "$filepath")
    dst="${archive_cat}/${DATE_PREFIX}-${filename}"
    if mv "$filepath" "$dst"; then
      log_info "pruned: ${category}/${filename} (TTL: ${ttl}d)"
      PRUNED=$((PRUNED + 1))
    else
      log_warn "failed to move: $filepath"
      ERRORS=$((ERRORS + 1))
    fi
  done < <(find "$cat_dir" -maxdepth 1 -name "*.md" -mtime "+${ttl}" -type f -print0 2>/dev/null || true)
done

log_info "pruning complete: ${PRUNED} pruned, ${ERRORS} errors"
