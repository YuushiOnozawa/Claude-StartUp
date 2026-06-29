# setup/600-codegraph.sh — CodeGraph インストール + MCP 登録
# Requires: ok, fail, MISSING_CMDS
[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- codegraph (callgraph MCP) ---"

if ! command -v npm &>/dev/null; then
  fail "npm が見つかりません（Node.js をインストールしてください）"
  MISSING_CMDS+=("node")
else
  if ! command -v codegraph &>/dev/null; then
    npm install -g @colbymchenry/codegraph 2>/dev/null \
      && ok "codegraph インストール完了" \
      || fail "codegraph インストール失敗"
  else
    ok "codegraph インストール済み"
  fi

  _SETTINGS_LOCAL="${HOME}/.claude/settings.local.json"
  _CODEGRAPH_BIN="$(command -v codegraph 2>/dev/null)"

  if [[ -n "$_CODEGRAPH_BIN" ]]; then
    [[ ! -f "$_SETTINGS_LOCAL" ]] && echo '{}' > "$_SETTINGS_LOCAL"

    if jq -e '.mcpServers["codegraph"]' "$_SETTINGS_LOCAL" &>/dev/null; then
      ok "codegraph MCP 登録済み"
    else
      _TMP=$(mktemp)
      if jq --arg bin "$_CODEGRAPH_BIN" \
          '.mcpServers["codegraph"] = {"type":"stdio","command":$bin,"args":[]}' \
          "$_SETTINGS_LOCAL" > "$_TMP"; then
        mv "$_TMP" "$_SETTINGS_LOCAL"
        ok "codegraph MCP 登録完了"
      else
        rm -f "$_TMP"
        fail "MCP 登録失敗"
      fi
    fi
  fi
fi

unset _SETTINGS_LOCAL _CODEGRAPH_BIN _TMP
