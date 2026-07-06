#!/bin/bash
# PostCompact hook (matcher: ""): 圧縮発生を marker file で記録する。
# 注入は UserPromptSubmit 側で行う。
# fail-open (常に exit 0)
set -uo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[[ -z "$SESSION_ID" ]] && exit 0

_TMPDIR=$(realpath -m "${TMPDIR:-/tmp}" 2>/dev/null || echo "/tmp")
[[ "${_TMPDIR}" = /* ]] || _TMPDIR="/tmp"

MARKER_DIR="${_TMPDIR}/claude-compacted"
mkdir -p "$MARKER_DIR" 2>/dev/null || true
printf '%s\n' "$(date +%s)" > "$MARKER_DIR/$SESSION_ID" 2>/dev/null || true

# compact が実行されたら閾値通知の cooldown をリセットする
rm -f "${_TMPDIR}/claude-compact-warned/$SESSION_ID" 2>/dev/null || true

exit 0
