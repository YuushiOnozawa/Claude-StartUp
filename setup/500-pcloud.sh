# setup/500-pcloud.sh — pCloud FUSE マウント (rclone) セットアップ
# Requires: ok, fail, MISSING_CMDS (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- pCloud (rclone) ---"

# rclone インストール確認
if ! command -v rclone &>/dev/null; then
  echo "  → rclone が未導入。インストールします..."
  # apt 版は WSL2 で FUSE マウントが動作しないため公式インストーラを使用
  # unzip は公式インストーラの展開に必要
  command -v unzip &>/dev/null || sudo apt-get install -y unzip >/dev/null 2>&1 || true
  if curl -fsSL https://rclone.org/install.sh | sudo bash; then
    ok "rclone (インストール完了)"
  else
    fail "rclone  →  手動: curl https://rclone.org/install.sh | sudo bash"
    MISSING_CMDS+=("rclone")
    return 0
  fi
else
  ok "rclone"
fi

# マウントポイントの作成
PCLOUD_MOUNT="$HOME/pcloud"
if [[ -d "$PCLOUD_MOUNT" ]]; then
  ok "マウントポイント $PCLOUD_MOUNT (作成済み)"
else
  mkdir -p "$PCLOUD_MOUNT"
  ok "マウントポイント作成: $PCLOUD_MOUNT"
fi

# pCloud リモート設定の確認
if rclone listremotes 2>/dev/null | grep -q '^pcloud:'; then
  ok "rclone pcloud リモート設定済み"
else
  echo "  ℹ  pCloud リモートが未設定です（要: 手動で OAuth 認証）:"
  echo "       rclone config"
  echo "     → n → 名前: pcloud → type: pcloud → OAuth 認証"
fi

# マウントコマンドのヒント
echo "  ℹ  マウント:   rclone mount pcloud: $PCLOUD_MOUNT --daemon --vfs-cache-mode writes"
echo "  ℹ  アンマウント: fusermount -u $PCLOUD_MOUNT"
