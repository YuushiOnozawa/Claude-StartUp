#!/usr/bin/env bash
# hooks/lib/logging.sh — hook スクリプト共通ログユーティリティ
# Usage: source "$(dirname "$0")/lib/logging.sh"

HOOK_LOG_DIR="${HOME}/.claude/hooks/logs"
mkdir -p "$HOOK_LOG_DIR"

# 呼び出し元スクリプト名（拡張子なし）
_HOOK_NAME="$(basename "${BASH_SOURCE[1]:-$0}" .sh)"
_HOOK_LOG="${HOOK_LOG_DIR}/${_HOOK_NAME}.log"

log() {
  local level="$1"; shift
  local msg="$*"
  printf '%s [%s] %s: %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$level" "$_HOOK_NAME" "$msg" \
    | tee -a "$_HOOK_LOG" >&2 || true
}

log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }
