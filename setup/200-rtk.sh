# setup/200-rtk.sh — RTK (Rust Token Killer) セットアップ
# Requires: ok, fail, ensure_local_bin_in_path, MISSING_CMDS (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

# --- RTK (Rust Token Killer): トークン削減プロキシ ---
if ! command -v rtk &>/dev/null; then
  echo "  → RTK が未導入。公式インストーラを実行: curl -fsSL …/install.sh | sh"
  if curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh; then
    ensure_local_bin_in_path
    ok "RTK (自動インストール完了)"
  else
    fail "RTK  →  手動: https://github.com/rtk-ai/rtk"
    MISSING_CMDS+=("rtk")
  fi
else
  ok "rtk"
  ensure_local_bin_in_path
fi

# RTK hook と RTK.md の初期化 (冪等)
if command -v rtk &>/dev/null; then
  echo "  → rtk init -g --auto-patch で hook と RTK.md を初期化..."
  if rtk init -g --auto-patch >/dev/null; then
    ok "RTK hook 初期化完了"
  else
    fail "RTK hook 初期化失敗  →  手動: rtk init -g"
    MISSING_CMDS+=("rtk-hook")
  fi
fi
