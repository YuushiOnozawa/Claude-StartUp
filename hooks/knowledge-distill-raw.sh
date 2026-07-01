#!/usr/bin/env bash
# knowledge-distill-raw: Raw session log 生成
# 引数: $1=TRANSCRIPT_PATH $2=DATE $3=PROJECT $4=TRANSCRIPT_BASE
set -euo pipefail

HOOK_DIR="$(dirname "$0")"
# shellcheck source=lib/logging.sh
source "${HOOK_DIR}/lib/logging.sh"
_HOOK_NAME="knowledge-distill"  # ログファイルを orchestrator と統一
_HOOK_LOG="${HOOK_LOG_DIR}/${_HOOK_NAME}.log"

TRANSCRIPT_PATH="$1"
DATE="$2"
PROJECT="$3"
TRANSCRIPT_BASE="$4"

RAW_DIR="$HOME/.local/share/claude-sessions"
RAW_FILE="${RAW_DIR}/${DATE}-${TRANSCRIPT_BASE}-${PROJECT}.md"

mkdir -p "$RAW_DIR"

SUCCESS=false
for i in 1 2 3; do
  if {
    printf -- '---\ndate: %s\nproject: %s\ntags: [session, raw-log]\n---\n\n# セッション記録 %s %s\n\n' \
      "$DATE" "$PROJECT" "$DATE" "$TRANSCRIPT_BASE"
    jq -rn '
      [inputs |
        ((.role // .type // "") | ascii_downcase) as $r |
        (
          (.message.content // .msg.content // .content // "") |
          if type == "array" then
            [.[] |
              if .type == "text" then .text
              elif .type == "tool_use" then
                "**Tool**: " + .name + " \u2192 " +
                  ((.input // {}) |
                  (to_entries | map(select(.value | type == "string")) | .[0].value //
                   (to_entries[0].value // "")) |
                  if type == "string" then .[0:80] else tostring[0:80] end)
              else empty end
            ] | join("\n")
          elif type == "string" then .
          else ""
          end
        ) as $body |
        if ($body | length) > 0 then
          if ($r == "human" or $r == "user") then "## User\n\($body)"
          elif $r == "assistant" then "## Claude\n\($body)"
          else empty end
        else empty end
      ] | join("\n\n---\n\n")
    ' "$TRANSCRIPT_PATH" 2>/dev/null
  } > "$RAW_FILE"; then
    echo "$RAW_FILE"
    log_info "raw log saved: $RAW_FILE"
    SUCCESS=true
    break
  fi
done

if [ "$SUCCESS" = false ]; then
  log_warn "raw log generation failed after 3 attempts (non-fatal)"
  rm -f "$RAW_FILE"
  exit 0
fi
