# setup/410-hooks-distill.sh — knowledge-rag: 蒸留パイプライン hook 配置・登録
# Hooks: knowledge-distill (SessionEnd), session-end-queue (SessionEnd)
# Requires: ok, fail, MISSING_CMDS (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- hooks: distill ---"

_KHOOK_DISTILL_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_KHOOK_SETTINGS="$HOME/.claude/settings.json"

# knowledge-distill hook スクリプトの実行権限を保証し SessionEnd に登録
KRAG_HOOK="$HOME/.claude/hooks/knowledge-distill.sh"
if [[ -f "$KRAG_HOOK" ]]; then
  chmod +x "$KRAG_HOOK"
  ok "knowledge-distill hook (chmod)"

  if [[ -f "$_KHOOK_SETTINGS" ]] && command -v jq &>/dev/null; then
    KRAG_HOOK_CMD="bash -c 'trap \"\" INT TERM; bash ${HOME}/.claude/hooks/knowledge-distill.sh 2> >(tee -a ${HOME}/.claude/hooks/knowledge-distill.log >&2)'"
    _krag_tmp="${_KHOOK_SETTINGS}.tmp"
    if jq --arg cmd "$KRAG_HOOK_CMD" '
      .hooks.SessionEnd //= [] |
      if (.hooks.SessionEnd | map(.hooks[]?.command // "") | any(contains("knowledge-distill.sh"))) then .
      else .hooks.SessionEnd += [{"hooks": [{"type": "command", "command": $cmd}]}]
      end
    ' "$_KHOOK_SETTINGS" > "$_krag_tmp" && mv "$_krag_tmp" "$_KHOOK_SETTINGS"; then
      ok "settings.json (SessionEnd: knowledge-distill)"
    else
      rm -f "$_krag_tmp"
      fail "settings.json の SessionEnd 更新に失敗"
      MISSING_CMDS+=("knowledge-distill-hook-settings")
    fi
  fi
fi

# session-end-queue hook スクリプトの配置と SessionEnd への登録
_KRAG_SEQ_SRC="${_KHOOK_DISTILL_REPO_DIR}/hooks/session-end-queue.sh"
_KRAG_SEQ_DST="$HOME/.claude/hooks/session-end-queue.sh"
if [[ -f "$_KRAG_SEQ_SRC" ]]; then
  if [[ "$_KRAG_SEQ_SRC" -ef "$_KRAG_SEQ_DST" ]]; then
    mkdir -p "$HOME/.claude/hooks/logs"
    ok "session-end-queue hook (配置済み)"
  elif cp "$_KRAG_SEQ_SRC" "$_KRAG_SEQ_DST" && chmod +x "$_KRAG_SEQ_DST"; then
    mkdir -p "$HOME/.claude/hooks/logs"
    ok "session-end-queue hook (配置)"
  else
    fail "session-end-queue.sh  →  手動: cp $_KRAG_SEQ_SRC $_KRAG_SEQ_DST"
  fi

  if [[ -f "$_KHOOK_SETTINGS" ]] && command -v jq &>/dev/null; then
    KRAG_SEQ_CMD="bash -c 'trap \"\" INT TERM; bash \"${HOME}/.claude/hooks/session-end-queue.sh\" 2>> \"${HOME}/.claude/hooks/logs/session-end-queue.log\"'"
    _krag_tmp="${_KHOOK_SETTINGS}.tmp"
    if jq --arg cmd "$KRAG_SEQ_CMD" '
      .hooks.SessionEnd //= [] |
      if (.hooks.SessionEnd | map(.hooks[]?.command // "") | any(contains("session-end-queue.sh"))) then .
      else .hooks.SessionEnd += [{"hooks": [{"type": "command", "command": $cmd}]}]
      end
    ' "$_KHOOK_SETTINGS" > "$_krag_tmp" && mv "$_krag_tmp" "$_KHOOK_SETTINGS"; then
      ok "settings.json (SessionEnd: session-end-queue)"
    else
      rm -f "$_krag_tmp"
      fail "settings.json の SessionEnd 更新に失敗"
      MISSING_CMDS+=("session-end-queue-hook-settings")
    fi
  fi
fi

unset _KHOOK_DISTILL_REPO_DIR _KHOOK_SETTINGS KRAG_HOOK KRAG_HOOK_CMD
unset _KRAG_SEQ_SRC _KRAG_SEQ_DST KRAG_SEQ_CMD _krag_tmp
