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

# hook 登録ヘルパー（冪等）: _register_hook <hook_type> <cmd> <label>
# 重複チェックはコマンド文字列の完全一致で行う
_register_hook() {
  local hook_type="$1" cmd="$2" label="$3"
  if jq --arg ht "$hook_type" --arg cmd "$cmd" '
    .hooks[$ht] //= [] |
    if (.hooks[$ht] | map(.hooks[]?.command // "") | any(. == $cmd)) then .
    else .hooks[$ht] += [{"hooks": [{"type": "command", "command": $cmd}]}]
    end
  ' "$_CMLC_SETTINGS" > "$_CMLC_TMP" && mv "$_CMLC_TMP" "$_CMLC_SETTINGS"; then
    ok "$label"
  else
    fail "$label"
    rm -f "$_CMLC_TMP"
  fi
}

_register_hook "Stop"             "bash ${HOME}/.claude/hooks/claude-md-stop.sh"       "Stop hook 登録"
_register_hook "UserPromptSubmit" "bash ${HOME}/.claude/hooks/claude-md-check.sh"      "UserPromptSubmit hook 登録"
_register_hook "Stop"             "bash ${HOME}/.claude/hooks/lessons-learned-stop.sh"  "Stop hook 登録 (lessons-learned)"
_register_hook "UserPromptSubmit" "bash ${HOME}/.claude/hooks/lessons-learned-check.sh" "UserPromptSubmit hook 登録 (lessons-learned)"

unset -f _register_hook
unset _CMLC_HOOK_SRC_DIR _CMLC_HOOK_DST_DIR _CMLC_SETTINGS _CMLC_TMP _src _rel _dst
