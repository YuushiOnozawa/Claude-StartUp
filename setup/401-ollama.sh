# setup/401-ollama.sh — Ollama インストール
# Requires: ok, fail, MISSING_CMDS (append-only)
# Note: モデルのダウンロードは 800-ollama-models.sh で行う

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- ollama: install ---"

if ! command -v ollama &>/dev/null; then
  echo "  → Ollama が未導入。公式インストーラを実行..."
  if curl -fsSL https://ollama.com/install.sh | sh; then
    ok "Ollama (自動インストール完了)"
  else
    fail "Ollama  →  手動: https://ollama.com/download"
    MISSING_CMDS+=("ollama")
  fi
else
  ok "ollama"
fi
