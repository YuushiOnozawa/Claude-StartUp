#!/bin/bash
# UserPromptSubmit hook: statusline が書いた warn marker を検出し、
# compact-prep 実行提案を注入する（one-shot + cooldown）。
# fail-open (常に exit 0)
set -uo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[[ -z "$SESSION_ID" ]] && exit 0

_TMPDIR=$(realpath -m "${TMPDIR:-/tmp}" 2>/dev/null || echo "/tmp")
[[ "${_TMPDIR}" = /* ]] || _TMPDIR="/tmp"

WARN_MARKER="${_TMPDIR}/claude-compact-warn/$SESSION_ID"
[[ -f "$WARN_MARKER" ]] || exit 0

CTX_PCT=$(cat "$WARN_MARKER" 2>/dev/null)
CTX_PCT=${CTX_PCT:-"?"}
rm -f "$WARN_MARKER" 2>/dev/null || true

# cooldown marker（statusline の再 warn を防止。compact 時にリセットされる）
WARNED_DIR="${_TMPDIR}/claude-compact-warned"
mkdir -p "$WARNED_DIR" 2>/dev/null || true
printf '%s\n' "$(date +%s)" > "$WARNED_DIR/$SESSION_ID" 2>/dev/null || true

CTX="[COMPACT PREP REMINDER] context 使用率が ${CTX_PCT}% に達した。"
CTX+=$'\n'"- 作業区切りでユーザーに \`/compact-prep\` の実行を提案せよ。"
CTX+=$'\n'"- \`/compact-prep\` 実行後、ユーザーに \`/compact\` 実行を案内せよ。"
CTX+=$'\n'"- scope 縮小や別セッション化ではなく、圧縮前 state 保存で対処せよ。"

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
exit 0
