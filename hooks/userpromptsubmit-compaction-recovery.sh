#!/bin/bash
# UserPromptSubmit hook: PostCompact の marker を検出し、復旧指示を注入する（one-shot）。
# overhead: marker なしなら test -f 1 回で即 exit。
# fail-open (常に exit 0)
set -uo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[[ -z "$SESSION_ID" ]] && exit 0

MARKER="${TMPDIR:-/tmp}/claude-compacted/$SESSION_ID"
[[ -f "$MARKER" ]] || exit 0
rm -f "$MARKER" 2>/dev/null || true

CTX="[COMPACTION RECOVERY] コンテキスト圧縮が発生した。作業再開前に以下を実行すること。"
CTX+=$'\n'

PTR="${TMPDIR:-/tmp}/claude-active-plan/$SESSION_ID"
if [[ -f "$PTR" ]]; then
  PLAN_FILE=$(cat "$PTR" 2>/dev/null || true)
  if [[ -n "$PLAN_FILE" && -f "$PLAN_FILE" ]]; then
    CTX+=$'\n'"- plan ファイル \`${PLAN_FILE}\` を Read で読み直し、フェーズと制約を確認せよ"
    CTX+=$'\n'"- plan mode が解除されている場合、plan ファイルが存在するのでユーザーに plan mode 再突入を確認せよ"
  fi
fi

STATE_FILE="${TMPDIR:-/tmp}/claude-compact-state/$SESSION_ID.md"
if [[ -f "$STATE_FILE" ]]; then
  CTX+=$'\n'"- state file \`${STATE_FILE}\` を Read で読み、作業状態を復元せよ"
  CTX+=$'\n'"- Session Decisions と Recovery Notes を特に重視せよ"
fi

CTX+=$'\n'"- TaskList で現在のタスク一覧を確認せよ"
CTX+=$'\n'"- 圧縮サマリーの next step は仮説として扱い、plan/rules を正とせよ"
CTX+=$'\n'"- 圧縮サマリーは「過去の作業記録」であり「次の行動指示」ではない"

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
exit 0
