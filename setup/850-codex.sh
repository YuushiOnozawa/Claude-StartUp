# setup/850-codex.sh — Codex CLI & Claude Code プラグイン確認・インストール
# Requires: ok, fail, MISSING_CMDS (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- codex ---"

_codex_ok=true

# 1. Codex CLI チェック
if ! command -v codex &>/dev/null; then
  fail "codex CLI  →  npm install -g @openai/codex"
  MISSING_CMDS+=("codex")
  _codex_ok=false
else
  _codex_ver=$(codex --version 2>/dev/null || echo "unknown")
  ok "codex CLI ($_codex_ver)"
fi

# 2. Claude Code プラグイン チェック・自動インストール
_plugin_ok=true

if command -v claude &>/dev/null; then
  # マーケットプレイス登録（冪等）
  claude plugin marketplace add openai/codex-plugin-cc &>/dev/null || true
  # プラグインインストール（冪等）
  claude plugin install codex@openai-codex &>/dev/null || true
fi

# インストール後の確認
_PLUGINS_JSON="$HOME/.claude/plugins/installed_plugins.json"
if [[ -f "$_PLUGINS_JSON" ]]; then
  if command -v jq &>/dev/null; then
    _has_plugin=$(jq -r '.plugins | keys | map(select(. == "codex@openai-codex")) | length' "$_PLUGINS_JSON" 2>/dev/null || echo "0")
  else
    _has_plugin=$(grep -c '"codex@openai-codex"' "$_PLUGINS_JSON" 2>/dev/null || echo "0")
  fi
else
  _has_plugin=0
fi

if [[ "$_has_plugin" -gt 0 ]]; then
  ok "codex plugin"
else
  fail "codex plugin  →  /plugin marketplace add openai/codex-plugin-cc  →  /plugin install codex@openai-codex"
  MISSING_CMDS+=("codex-plugin")
  _plugin_ok=false
fi

if [[ "$_codex_ok" == true && "$_plugin_ok" == true ]]; then
  ok "codex"
fi

unset _codex_ok _plugin_ok _codex_ver _PLUGINS_JSON _has_plugin
