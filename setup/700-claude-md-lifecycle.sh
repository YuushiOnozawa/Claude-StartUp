# setup/700-claude-md-lifecycle.sh — CLAUDE.md ライフサイクル管理フックのセットアップ
# Requires: ok, fail (from setup.sh)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- CLAUDE.md lifecycle ---"

_CMLC_HOOK_SRC_DIR="$(dirname "${BASH_SOURCE[0]}")/../hooks"
_CMLC_HOOK_DST_DIR="$HOME/.claude/hooks"
_CMLC_SETTINGS="$HOME/.claude/settings.json"
_CMLC_TMP="${_CMLC_SETTINGS}.claude-md-lifecycle.tmp"

mkdir -p "$_CMLC_HOOK_DST_DIR"

# フックファイルをコピー（hooks/ 配下の全 .sh と lib/ ディレクトリを一括）
# 注意: hooks/ 配下の全 .sh が自動配置される。配置対象外ファイルは hooks/ の外に置くこと
mkdir -p "$_CMLC_HOOK_DST_DIR/lib"
[[ -d "${_CMLC_HOOK_SRC_DIR}/lib" ]] || echo "  ℹ  hooks/lib/ が見つかりません。lib/ スクリプトはスキップされます。"
for _src in "${_CMLC_HOOK_SRC_DIR}"/*.sh "${_CMLC_HOOK_SRC_DIR}"/lib/*.sh; do
  [[ -f "$_src" ]] || continue
  _rel="${_src#${_CMLC_HOOK_SRC_DIR}/}"
  _dst="${_CMLC_HOOK_DST_DIR}/${_rel}"
  mkdir -p "$(dirname "$_dst")"
  if cp "$_src" "$_dst" && chmod +x "$_dst"; then
    ok "${_rel}"
  else
    fail "${_rel}  →  手動: cp ${_src} ${_dst} && chmod +x ${_dst}"
    MISSING_CMDS+=("${_rel}")
  fi
done

# settings.json が存在しなければ初期化
if [[ ! -f "$_CMLC_SETTINGS" ]]; then
  echo '{}' > "$_CMLC_SETTINGS"
fi

# Stop hook 登録（冪等）
_CMLC_STOP_CMD="bash ${HOME}/.claude/hooks/claude-md-stop.sh"
if jq --arg cmd "$_CMLC_STOP_CMD" '
  .hooks.Stop //= [] |
  if (.hooks.Stop | map(.hooks[]?.command // "") | any(contains("claude-md-stop.sh"))) then .
  else .hooks.Stop += [{"hooks": [{"type": "command", "command": $cmd}]}]
  end
' "$_CMLC_SETTINGS" > "$_CMLC_TMP" && mv "$_CMLC_TMP" "$_CMLC_SETTINGS"; then
  ok "Stop hook 登録"
else
  fail "Stop hook 登録"
  rm -f "$_CMLC_TMP"
fi

# UserPromptSubmit hook 登録（冪等）
_CMLC_CHECK_CMD="bash ${HOME}/.claude/hooks/claude-md-check.sh"
if jq --arg cmd "$_CMLC_CHECK_CMD" '
  .hooks.UserPromptSubmit //= [] |
  if (.hooks.UserPromptSubmit | map(.hooks[]?.command // "") | any(contains("claude-md-check.sh"))) then .
  else .hooks.UserPromptSubmit += [{"hooks": [{"type": "command", "command": $cmd}]}]
  end
' "$_CMLC_SETTINGS" > "$_CMLC_TMP" && mv "$_CMLC_TMP" "$_CMLC_SETTINGS"; then
  ok "UserPromptSubmit hook 登録"
else
  fail "UserPromptSubmit hook 登録"
  rm -f "$_CMLC_TMP"
fi

# Stop hook 登録（lessons-learned-stop.sh / 冪等）
_LL_STOP_CMD="bash ${HOME}/.claude/hooks/lessons-learned-stop.sh"
if jq --arg cmd "$_LL_STOP_CMD" '
  .hooks.Stop //= [] |
  if (.hooks.Stop | map(.hooks[]?.command // "") | any(contains("lessons-learned-stop.sh"))) then .
  else .hooks.Stop += [{"hooks": [{"type": "command", "command": $cmd}]}]
  end
' "$_CMLC_SETTINGS" > "$_CMLC_TMP" && mv "$_CMLC_TMP" "$_CMLC_SETTINGS"; then
  ok "Stop hook 登録 (lessons-learned)"
else
  fail "Stop hook 登録 (lessons-learned)"
  rm -f "$_CMLC_TMP"
fi

# UserPromptSubmit hook 登録（lessons-learned-check.sh / 冪等）
_LL_CHECK_CMD="bash ${HOME}/.claude/hooks/lessons-learned-check.sh"
if jq --arg cmd "$_LL_CHECK_CMD" '
  .hooks.UserPromptSubmit //= [] |
  if (.hooks.UserPromptSubmit | map(.hooks[]?.command // "") | any(contains("lessons-learned-check.sh"))) then .
  else .hooks.UserPromptSubmit += [{"hooks": [{"type": "command", "command": $cmd}]}]
  end
' "$_CMLC_SETTINGS" > "$_CMLC_TMP" && mv "$_CMLC_TMP" "$_CMLC_SETTINGS"; then
  ok "UserPromptSubmit hook 登録 (lessons-learned)"
else
  fail "UserPromptSubmit hook 登録 (lessons-learned)"
  rm -f "$_CMLC_TMP"
fi

unset _CMLC_HOOK_SRC_DIR _CMLC_HOOK_DST_DIR _CMLC_SETTINGS _CMLC_TMP
unset _CMLC_STOP_CMD _CMLC_CHECK_CMD _LL_STOP_CMD _LL_CHECK_CMD _src _rel _dst
