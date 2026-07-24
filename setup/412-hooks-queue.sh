# setup/412-hooks-queue.sh — knowledge-rag: キュー制御 hook 配置・登録
# Hooks: check-queue (UserPromptSubmit)
# Requires: ok, fail, MISSING_CMDS (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- hooks: queue ---"

_KHOOK_SETTINGS="$HOME/.claude/settings.json"

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

unset _KHOOK_SETTINGS KRAG_CQ_HOOK KRAG_CQ_CMD _krag_tmp
