#!/usr/bin/env bash
# knowledge-prune: SessionEnd hook
# TTL を超過したドキュメントを ~/pcloud/obsidian/archive/ に移動し、
# ChromaDB + index_metadata.json から削除する。

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
KRAG_DIR="$HOME/.local/share/knowledge-rag"
PROJECT_DIR="$HOME/srcs/Claude-StartUp"

# キュードレイン（リトライ実行時はスキップして無限ループを防ぐ）
if [[ "${KRAG_PRUNE_RETRY:-0}" != "1" ]] && mountpoint -q "$HOME/pcloud" 2>/dev/null; then
  _prune_retry_callback() {
    # item_file は使わない（pruning は状態に依存しないため）
    log_info "retrying queued prune"
    KRAG_PRUNE_RETRY=1 bash "${_PRUNE_HOOK_DIR}/knowledge-prune.sh"
  }
  _PRUNE_HOOK_DIR="$HOOK_DIR"
  queue_drain "$HOOK_NAME" "pcloud" "_prune_retry_callback"
fi

# pCloud マウント確認 → 未マウントならキューに積んで終了
if ! mountpoint -q "$HOME/pcloud" 2>/dev/null; then
  log_info "pCloud not mounted, queuing"
  queue_push "$HOOK_NAME" "pcloud" "" ""
  exit 0
fi

# MCP サーバーの設定ファイルを使用（git 追跡の config.example.yaml から生成される）
KRAG_CONFIG="${KRAG_DIR}/config.yaml"
VENV_PYTHON="${KRAG_DIR}/venv/bin/python3"

# decay.enabled 確認（venv の python を使用して PyYAML を確実にロードする）
ENABLED=$(
  "${VENV_PYTHON}" -c \
    "import yaml; c=yaml.safe_load(open('${KRAG_CONFIG}')); print(c.get('decay',{}).get('enabled','false'))" \
    2>/dev/null || echo "false"
)
if [[ "$ENABLED" != "True" && "$ENABLED" != "true" ]]; then
  log_info "decay disabled, skipping"
  exit 0
fi

log_info "starting knowledge pruning"
"${VENV_PYTHON}" "${PROJECT_DIR}/scripts/knowledge-prune.py" \
  --config "${KRAG_CONFIG}" \
  --data-dir "${KRAG_DIR}/data"
log_info "pruning complete"
