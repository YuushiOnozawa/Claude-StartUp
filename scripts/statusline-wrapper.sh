#!/bin/bash
# statusline wrapper: 表示は ccstatusline にパススルー。副業として warn marker 判定。
# marker 処理のいかなる失敗も表示を壊してはならない（fail-open）。
set -uo pipefail
INPUT=$(cat)

{
  COMPACT_WARN_THRESHOLD=75   # 不変条件: CLAUDE_AUTOCOMPACT_PCT_OVERRIDE (85) より 10pt 以上低く保つ
  CONTEXT_LIMIT=200000
  session_id=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
  transcript=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
  if [[ -n "$session_id" && -n "$transcript" && -f "$transcript" ]] \
     && [[ ! -f "${TMPDIR:-/tmp}/claude-compact-warned/$session_id" ]]; then
    # 直近の usage エントリから context 消費を推定（head -1 で早期打ち切り）
    used=$(tac "$transcript" | jq -r '
      select(.message.usage != null) |
      (.message.usage.input_tokens // 0)
      + (.message.usage.cache_creation_input_tokens // 0)
      + (.message.usage.cache_read_input_tokens // 0)' 2>/dev/null | head -1)
    if [[ "$used" =~ ^[0-9]+$ ]]; then
      int_pct=$(( used * 100 / CONTEXT_LIMIT ))
      if [ "$int_pct" -ge "$COMPACT_WARN_THRESHOLD" ]; then
        mkdir -p "${TMPDIR:-/tmp}/claude-compact-warn"
        printf '%s\n' "$int_pct" > "${TMPDIR:-/tmp}/claude-compact-warn/$session_id"
      fi
    fi
  fi
} 2>/dev/null || true

# 表示: ccstatusline へパススルー（Phase 0-3 で確認したフルパス）
printf '%s' "$INPUT" | /home/ylocal/.local/share/mise/installs/node/24/bin/ccstatusline
