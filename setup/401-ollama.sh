# setup/401-ollama.sh — Ollama インストール
# Requires: ok, fail, MISSING_CMDS (append-only)
# Note: モデルのダウンロードは 800-ollama-models.sh で行う

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- ollama: install ---"

# zstd は Ollama 公式インストーラの展開に必要
if ! command -v zstd &>/dev/null; then
  echo "  → zstd が未導入。インストール..."
  if sudo apt-get install -y zstd &>/dev/null 2>&1 || sudo brew install zstd &>/dev/null 2>&1; then
    ok "zstd"
  else
    fail "zstd  →  手動: sudo apt install zstd"
    MISSING_CMDS+=("zstd")
  fi
fi

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
