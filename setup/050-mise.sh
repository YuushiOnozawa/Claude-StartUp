# setup/050-mise.sh — mise (多言語バージョン管理) セットアップ
# Requires: ok, fail, MISSING_CMDS (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- mise ---"

# --- mise インストール ---
if ! command -v mise &>/dev/null; then
  echo "  → mise が未導入。公式インストーラを実行..."
  if curl -fsSL https://mise.run | sh; then
    export PATH="$HOME/.local/bin:$PATH"
    ok "mise (自動インストール完了)"
  else
    fail "mise  →  手動: curl https://mise.run | sh"
    MISSING_CMDS+=("mise")
    return 0
  fi
else
  ok "mise"
fi

# シムディレクトリを現セッション PATH に追加（source 経由なので後続モジュールにも継承）
export PATH="$HOME/.local/share/mise/shims:$PATH"

# --- node@22 グローバルインストール ---
if ! mise ls --global 2>/dev/null | grep -q "^node.*22"; then
  echo "  → mise install node@22..."
  if mise use -g node@22; then
    ok "node@22 (mise)"
  else
    fail "node@22  →  手動: mise use -g node@22"
    MISSING_CMDS+=("nodejs-v22")
  fi
else
  ok "node@22 (mise 既存)"
fi

# --- python@3.11 グローバルインストール ---
if ! mise ls --global 2>/dev/null | grep -q "^python.*3\.11"; then
  echo "  → mise install python@3.11..."
  if mise use -g python@3.11; then
    ok "python@3.11 (mise)"
  else
    fail "python@3.11  →  手動: mise use -g python@3.11"
    MISSING_CMDS+=("python3.11+")
  fi
else
  ok "python@3.11 (mise 既存)"
fi

# --- ~/.bashrc / ~/.zshrc に mise activate を追記（マーカー方式で冪等）---
_MISE_MARKER="# Claude-StartUp: mise activate"
_MISE_LINE='eval "$(~/.local/bin/mise activate bash)"'
_MISE_ZLINE='eval "$(~/.local/bin/mise activate zsh)"'

for _rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ -f "$_rc" ]] || continue
  if ! grep -qF "$_MISE_MARKER" "$_rc"; then
    {
      echo ""
      echo "$_MISE_MARKER"
      if [[ "$_rc" == *zshrc ]]; then
        echo "$_MISE_ZLINE"
      else
        echo "$_MISE_LINE"
      fi
    } >> "$_rc"
    ok "mise activate 追記: $_rc"
  fi
done
