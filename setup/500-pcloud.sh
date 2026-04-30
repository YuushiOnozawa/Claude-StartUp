# setup/500-pcloud.sh — pCloud FUSE マウント (rclone) セットアップ
# Requires: ok, fail, MISSING_CMDS (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- pCloud (rclone) ---"

# rclone インストール確認
if ! command -v rclone &>/dev/null; then
  echo "  → rclone が未導入。インストールします..."
  if sudo apt-get install -y rclone >/dev/null 2>&1; then
    ok "rclone (インストール完了)"
  else
    fail "rclone  →  手動: sudo apt-get install -y rclone"
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
  echo "  ℹ  pCloud リモートが未設定です。以下を実行してください:"
  echo "       rclone config"
  echo "     → n (new remote) → 名前: pcloud → type: pcloud → OAuth 認証"
  MISSING_CMDS+=("rclone-pcloud-config")
fi

# マウントコマンドのヒント
echo "  ℹ  マウント:   rclone mount pcloud: $PCLOUD_MOUNT --daemon --vfs-cache-mode writes"
echo "  ℹ  アンマウント: fusermount -u $PCLOUD_MOUNT"
