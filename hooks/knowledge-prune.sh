#!/usr/bin/env bash
# knowledge-prune: SessionEnd hook (bash-only, Issue #92)
# TTL 超過ファイルを archive/ に mv する。
# 次回 MCP サーバー起動時にインクリメンタルインデックスが orphan を自動削除。

set -euo pipefail
# 終了コード方針（カテゴリ B / Issue #51）:
#   exit 0 — 想定内スキップ（documents dir 未存在）
#   非ゼロ  — 想定外エラー（set -euo pipefail による自動終了）

HOOK_DIR="$(dirname "$0")"

# shellcheck source=lib/logging.sh
source "${HOOK_DIR}/lib/logging.sh"

DOCS_DIR="$HOME/.local/share/knowledge-rag/documents"
ARCHIVE_DIR="$HOME/.local/share/knowledge-rag/archive"

# カテゴリ別 TTL（日数）。-1 は永続保持。
declare -A CATEGORY_TTL=(
  [sessions]=30
  [knowledge]=365
  [investigations]=180
  [lessons-learned]=-1
  [general]=90
)

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
