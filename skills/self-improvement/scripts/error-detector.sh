#!/bin/bash
# Self-Improvement Error Detector Hook
# PostToolUse hook for Bash commands (Claude Code / Codex / Copilot CLI)
# Detects command failures and prompts logging to .learnings/ERRORS.md

INPUT=$(cat)

json_extract() {
  # $1 = jq expr, $2 = python fallback expression (uses dict `d`)
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    exec(sys.argv[1])
except Exception:
    pass
" "$2" 2>/dev/null || true
  fi
}

# Filter to shell commands only (for agents without matcher support)
TOOL_NAME=$(json_extract '.tool_name // .toolName // ""' 'print(d.get("tool_name") or d.get("toolName") or "")')
if [ -n "$TOOL_NAME" ] && ! printf '%s' "$TOOL_NAME" | grep -qiE '^bash$|^shell$'; then
  exit 0
fi

# Extract tool output text
OUTPUT=$(json_extract '(.tool_response // .toolResult.textResultForLlm // "") | tostring' 'print(json.dumps(d.get("tool_response") or (d.get("toolResult") or {}).get("textResultForLlm") or ""))')
[ -n "$OUTPUT" ] || OUTPUT="$INPUT"

# Copilot explicit failure signal
RESULT_TYPE=$(json_extract '.toolResult.resultType // ""' 'print((d.get("toolResult") or {}).get("resultType") or "")')

# Error patterns to detect
ERROR_PATTERNS=(
  "error:"
  "Error:"
  "ERROR:"
  "failed"
  "FAILED"
  "command not found"
  "No such file"
  "Permission denied"
  "fatal:"
  "Exception"
  "Traceback"
  "npm ERR!"
  "ModuleNotFoundError"
  "SyntaxError"
  "TypeError"
  "exit code"
  "non-zero"
)

contains_error=false

if [ "$RESULT_TYPE" = "failure" ]; then
  contains_error=true
fi

for pattern in "${ERROR_PATTERNS[@]}"; do
  if [[ "$OUTPUT" == *"$pattern"* ]]; then
    contains_error=true
    break
  fi
done

if [ "$contains_error" = true ]; then
  cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "<error-detected>\nコマンドエラーが検出されました。以下に該当する場合は .learnings/ERRORS.md に ERR エントリを記録してください:\n- 予期しないエラーまたは原因が自明でないエラー\n- 調査・解決に時間を要したエラー\n- 同じコンテキストで再発する可能性があるエラー\n- 解決策が将来のセッションでも役立つエラー\n\nself-improvement スキルの形式: [ERR-YYYYMMDD-XXX]\n</error-detected>"
  }
}
EOF
fi
