# setup/411-hooks-auto.sh — knowledge-rag: 自動メンテナンス hook 配置・登録
# Hooks: knowledge-auto-promote (copy only), knowledge-prune (SessionEnd)
# Requires: ok, fail, MISSING_CMDS (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- hooks: auto ---"

_KHOOK_AUTO_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_KHOOK_SETTINGS="$HOME/.claude/settings.json"

# knowledge-auto-promote.sh の配置（hooks/ → ~/.claude/hooks/）
_KRAG_PROMOTE_SRC="${_KHOOK_AUTO_REPO_DIR}/hooks/knowledge-auto-promote.sh"
_KRAG_PROMOTE_DST="$HOME/.claude/hooks/knowledge-auto-promote.sh"
if [[ -f "$_KRAG_PROMOTE_SRC" ]]; then
  if [[ "$_KRAG_PROMOTE_SRC" -ef "$_KRAG_PROMOTE_DST" ]]; then
    ok "knowledge-auto-promote.sh (配置済み)"
  elif cp "$_KRAG_PROMOTE_SRC" "$_KRAG_PROMOTE_DST" && chmod +x "$_KRAG_PROMOTE_DST"; then
    ok "knowledge-auto-promote.sh"
  else
    fail "knowledge-auto-promote.sh  →  手動: cp $_KRAG_PROMOTE_SRC $_KRAG_PROMOTE_DST"
  fi
fi

# knowledge-prune.sh の配置と SessionEnd 登録（bash-only decay/pruning, Issue #92/#103）
_KRAG_PRUNE_SRC="${_KHOOK_AUTO_REPO_DIR}/hooks/knowledge-prune.sh"
_KRAG_PRUNE_DST="$HOME/.claude/hooks/knowledge-prune.sh"
if [[ -f "$_KRAG_PRUNE_SRC" ]]; then
  if [[ "$_KRAG_PRUNE_SRC" -ef "$_KRAG_PRUNE_DST" ]]; then
    ok "knowledge-prune.sh (配置済み)"
  elif cp "$_KRAG_PRUNE_SRC" "$_KRAG_PRUNE_DST" && chmod +x "$_KRAG_PRUNE_DST"; then
    ok "knowledge-prune.sh (配置)"
  else
    fail "knowledge-prune.sh  →  手動: cp $_KRAG_PRUNE_SRC $_KRAG_PRUNE_DST"
  fi

  if [[ -f "$_KHOOK_SETTINGS" ]] && command -v jq &>/dev/null; then
    _KRAG_PRUNE_CMD="bash -c 'trap \"\" INT TERM; bash \"${HOME}/.claude/hooks/knowledge-prune.sh\" 2>> \"${HOME}/.claude/hooks/logs/knowledge-prune.log\"'"
    _krag_tmp="${_KHOOK_SETTINGS}.tmp"
    if jq --arg cmd "$_KRAG_PRUNE_CMD" '
      .hooks.SessionEnd //= [] |
      if (.hooks.SessionEnd | map(.hooks[]?.command // "") | any(contains("knowledge-prune.sh"))) then .
      else .hooks.SessionEnd += [{"hooks": [{"type": "command", "command": $cmd}]}]
      end
    ' "$_KHOOK_SETTINGS" > "$_krag_tmp" && mv "$_krag_tmp" "$_KHOOK_SETTINGS"; then
      ok "settings.json (SessionEnd: knowledge-prune)"
    else
      rm -f "$_krag_tmp"
      fail "settings.json の SessionEnd 更新に失敗"
      MISSING_CMDS+=("knowledge-prune-hook-settings")
    fi
  fi
fi

unset _KHOOK_AUTO_REPO_DIR _KHOOK_SETTINGS
unset _KRAG_PROMOTE_SRC _KRAG_PROMOTE_DST
unset _KRAG_PRUNE_SRC _KRAG_PRUNE_DST _KRAG_PRUNE_CMD _krag_tmp
