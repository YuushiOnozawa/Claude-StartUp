# setup/412-hooks-queue.sh — knowledge-rag: キュー制御 hook 配置・登録
# Hooks: session-end-queue (SessionEnd), check-queue (UserPromptSubmit)
# Requires: ok, fail, MISSING_CMDS (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- hooks: queue ---"

_KHOOK_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude/hooks/logs"
[[ -f "$_KHOOK_SETTINGS" ]] || echo '{}' > "$_KHOOK_SETTINGS"

# session-end-queue.sh の実行権限を保証し SessionEnd に登録
KRAG_SEQ_HOOK="$HOME/.claude/hooks/session-end-queue.sh"
if [[ -f "$KRAG_SEQ_HOOK" ]]; then
  chmod +x "$KRAG_SEQ_HOOK"
  ok "session-end-queue hook (chmod)"
fi

if command -v jq &>/dev/null; then
  KRAG_SEQ_CMD="bash ${HOME}/.claude/hooks/session-end-queue.sh 2>> ${HOME}/.claude/hooks/logs/session-end-queue.log"
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

# check-queue hook スクリプトの実行権限を保証し UserPromptSubmit に登録
KRAG_CQ_HOOK="$HOME/.claude/hooks/check-queue.sh"
if [[ -f "$KRAG_CQ_HOOK" ]]; then
  chmod +x "$KRAG_CQ_HOOK"
  ok "check-queue hook (chmod)"

  if [[ -f "$_KHOOK_SETTINGS" ]] && command -v jq &>/dev/null; then
    KRAG_CQ_CMD="bash ${HOME}/.claude/hooks/check-queue.sh"
    _krag_tmp="${_KHOOK_SETTINGS}.tmp"
    if jq --arg cmd "$KRAG_CQ_CMD" '
      .hooks.UserPromptSubmit //= [] |
      if (.hooks.UserPromptSubmit | map(.hooks[]?.command // "") | any(contains("check-queue.sh"))) then .
      else .hooks.UserPromptSubmit += [{"hooks": [{"type": "command", "command": $cmd}]}]
      end
    ' "$_KHOOK_SETTINGS" > "$_krag_tmp" && mv "$_krag_tmp" "$_KHOOK_SETTINGS"; then
      ok "settings.json (UserPromptSubmit: check-queue)"
    else
      rm -f "$_krag_tmp"
      fail "settings.json の UserPromptSubmit 更新に失敗"
      MISSING_CMDS+=("check-queue-hook-settings")
    fi
  fi
fi

unset _KHOOK_SETTINGS KRAG_SEQ_HOOK KRAG_SEQ_CMD KRAG_CQ_HOOK KRAG_CQ_CMD _krag_tmp
