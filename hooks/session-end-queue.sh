#!/usr/bin/env bash
# session-end-queue: SessionEnd hook
# Queues session transcript for knowledge-distill at next SessionStart.
# Category B: expected skip → exit 0, unexpected error → non-zero (set -euo pipefail)

set -euo pipefail

HOOK_DIR="$(dirname "$0")"
source "${HOOK_DIR}/lib/logging.sh"
source "${HOOK_DIR}/lib/queue.sh"

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)

if [[ -z "$TRANSCRIPT_PATH" ]]; then
  log_info "no transcript_path, skipping"
  exit 0
fi

queue_push "knowledge-distill" "pending" "$TRANSCRIPT_PATH" "$CWD" \
  || log_warn "queue_push failed for $(basename "$TRANSCRIPT_PATH")"

log_info "queued: $(basename "$TRANSCRIPT_PATH")"
