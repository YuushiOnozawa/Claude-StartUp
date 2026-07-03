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
  _codex_ver="${_codex_ver//[^0-9.a-zA-Z-]/}"
  ok "codex CLI ($_codex_ver)"
fi

# 2. Claude Code プラグイン チェック・インストール
_plugin_ok=true

if command -v claude &>/dev/null; then
  if claude plugin list 2>/dev/null | grep -q "codex@openai-codex"; then
    echo "  [SKIP] codex plugin — 導入済み"
  else
    # マーケットプレイス登録（冪等）
    claude plugin marketplace add openai/codex-plugin-cc &>/dev/null || true
    # プラグインインストール
    if claude plugin install codex@openai-codex &>/dev/null; then
      echo "  [DONE] codex plugin"
    else
      fail "codex plugin  →  /plugin marketplace add openai/codex-plugin-cc  →  /plugin install codex@openai-codex"
      MISSING_CMDS+=("codex-plugin")
      _plugin_ok=false
    fi
  fi
else
  fail "codex plugin  →  /plugin marketplace add openai/codex-plugin-cc  →  /plugin install codex@openai-codex"
  MISSING_CMDS+=("codex-plugin")
  _plugin_ok=false
fi

if [[ "$_codex_ok" == true && "$_plugin_ok" == true ]]; then
  ok "codex"
fi

unset _codex_ok _plugin_ok _codex_ver
