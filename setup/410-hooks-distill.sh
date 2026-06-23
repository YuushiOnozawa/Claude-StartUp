# setup/410-hooks-distill.sh — knowledge-rag: 蒸留パイプライン hook 配置・登録
# Hooks: knowledge-distill (SessionEnd), lessons-learned-distill (SessionEnd)
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

# lessons-learned-distill hook の SessionEnd 登録（Ollama ベースのミス検知、Issue #XXX）
_KRAG_LL_SRC="${_KHOOK_DISTILL_REPO_DIR}/hooks/lessons-learned-distill.sh"
_KRAG_LL_DST="$HOME/.claude/hooks/lessons-learned-distill.sh"
if [[ -f "$_KRAG_LL_SRC" ]]; then
  if [[ "$_KRAG_LL_SRC" -ef "$_KRAG_LL_DST" ]]; then
    ok "lessons-learned-distill.sh (配置済み)"
  elif cp "$_KRAG_LL_SRC" "$_KRAG_LL_DST" && chmod +x "$_KRAG_LL_DST"; then
    ok "lessons-learned-distill.sh (配置)"
  else
    fail "lessons-learned-distill.sh  →  手動: cp $_KRAG_LL_SRC $_KRAG_LL_DST"
  fi

  if [[ -f "$_KHOOK_SETTINGS" ]] && command -v jq &>/dev/null; then
    KRAG_LL_CMD="bash -c 'trap \"\" INT TERM; bash \"${HOME}/.claude/hooks/lessons-learned-distill.sh\" 2>> \"${HOME}/.claude/hooks/logs/lessons-learned-distill.log\"'"
    _krag_tmp="${_KHOOK_SETTINGS}.tmp"
    if jq --arg cmd "$KRAG_LL_CMD" '
      .hooks.SessionEnd //= [] |
      if (.hooks.SessionEnd | map(.hooks[]?.command // "") | any(contains("lessons-learned-distill.sh"))) then .
      else .hooks.SessionEnd += [{"hooks": [{"type": "command", "command": $cmd}]}]
      end
    ' "$_KHOOK_SETTINGS" > "$_krag_tmp" && mv "$_krag_tmp" "$_KHOOK_SETTINGS"; then
      ok "settings.json (SessionEnd: lessons-learned-distill)"
    else
      rm -f "$_krag_tmp"
      fail "settings.json の SessionEnd 更新に失敗"
      MISSING_CMDS+=("lessons-learned-distill-hook-settings")
    fi
  fi
fi

unset _KHOOK_DISTILL_REPO_DIR _KHOOK_SETTINGS KRAG_HOOK KRAG_HOOK_CMD
unset _KRAG_LL_SRC _KRAG_LL_DST KRAG_LL_CMD _krag_tmp
