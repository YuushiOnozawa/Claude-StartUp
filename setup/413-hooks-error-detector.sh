# setup/413-hooks-error-detector.sh — error-detector hook 配置・登録
# Hooks: error-detector (PostToolUse)
# Requires: ok, fail, MISSING_CMDS (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- hooks: error-detector ---"

_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_413_SETTINGS="$HOME/.claude/settings.json"
_413_SRC="${_REPO_DIR}/hooks/error-detector.sh"
_413_DST="$HOME/.claude/hooks/error-detector.sh"
_413_DEPLOYED=false

mkdir -p "$HOME/.claude/hooks"
if [[ -L "$_413_SETTINGS" ]]; then
  fail "settings.json が symlink のため更新をスキップ"
else
  [[ -f "$_413_SETTINGS" ]] || echo '{}' > "$_413_SETTINGS"
fi

# setup/700 の一括コピーと意図的に重複（413 単体実行の自己完結保証）
if [[ -f "$_413_SRC" ]]; then
  if [[ "$_413_SRC" -ef "$_413_DST" ]]; then
    ok "error-detector.sh (配置済み)"
    _413_DEPLOYED=true
  elif cp "$_413_SRC" "$_413_DST" && chmod +x "$_413_DST"; then
    ok "error-detector.sh"
    _413_DEPLOYED=true
  else
    fail "error-detector.sh  →  手動: cp $_413_SRC $_413_DST"
    MISSING_CMDS+=("error-detector-hook")
  fi
else
  fail "error-detector.sh  →  手動: cp $_413_SRC $_413_DST"
  MISSING_CMDS+=("error-detector-hook")
fi

if [[ "$_413_DEPLOYED" == true && ! -L "$_413_SETTINGS" ]] && command -v jq &>/dev/null; then
  _413_CMD="bash ${HOME}/.claude/hooks/error-detector.sh"
  _413_TMP="${_413_SETTINGS}.tmp"
  if jq --arg cmd "$_413_CMD" '
    .hooks.PostToolUse //= [] |
    .hooks.PostToolUse |= (
      map(.hooks |= (
        if . then map(select((.command // "") | (type == "string" and contains("error-detector.sh")) | not))
        else . end
      ))
      | map(select((.hooks // []) | length > 0))
    ) |
    .hooks.PostToolUse += [{"hooks": [{"type": "command", "command": $cmd}]}]
  ' "$_413_SETTINGS" > "$_413_TMP" && mv "$_413_TMP" "$_413_SETTINGS"; then
    ok "settings.json (PostToolUse: error-detector)"
  else
    rm -f "$_413_TMP"
    fail "settings.json の PostToolUse 更新に失敗"
    MISSING_CMDS+=("error-detector-hook-settings")
  fi
fi

unset _REPO_DIR _413_SETTINGS _413_SRC _413_DST _413_DEPLOYED _413_CMD _413_TMP
