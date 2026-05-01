# setup/500-pcloud.sh — pCloud FUSE マウント (rclone) セットアップ
# Requires: ok, fail, MISSING_CMDS (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- pCloud (rclone) ---"

# rclone インストール確認
# apt 版 (v1.60.x) は WSL2 で FUSE マウントが動作しないため公式インストーラを使用
RCLONE_NEEDS_INSTALL=false
if command -v rclone &>/dev/null; then
  RCLONE_VER="$(rclone --version 2>/dev/null | head -1)"
  if echo "$RCLONE_VER" | grep -qE 'v1\.60(\.|$| )'; then
    echo "  → rclone v1.60 (apt版, WSL2 FUSE非対応) を検出。最新版に置換します..."
    sudo apt-get remove -y rclone >/dev/null 2>&1 || true
    RCLONE_NEEDS_INSTALL=true
  else
    ok "rclone ($RCLONE_VER)"
  fi
else
  echo "  → rclone が未導入。インストールします..."
  RCLONE_NEEDS_INSTALL=true
fi

if $RCLONE_NEEDS_INSTALL; then
  # unzip は公式インストーラの展開に必要
  if ! command -v unzip &>/dev/null; then
    echo "  → unzip が未導入。インストールします..."
    if sudo apt-get install -y unzip > /dev/null; then
      ok "unzip (インストール完了)"
    else
      fail "unzip  →  手動: sudo apt-get install -y unzip"
      MISSING_CMDS+=("unzip")
      return 0
    fi
  fi

  if curl -fsSL https://rclone.org/install.sh | sudo bash; then
    ok "rclone (インストール完了)"
  else
    fail "rclone  →  手動: curl https://rclone.org/install.sh | sudo bash"
    MISSING_CMDS+=("rclone")
    return 0
  fi
fi

# マウントポイントの作成
PCLOUD_MOUNT="$HOME/pcloud"
if [[ -d "$PCLOUD_MOUNT" ]]; then
  ok "マウントポイント $PCLOUD_MOUNT (作成済み)"
else
  mkdir -p "$PCLOUD_MOUNT"
  ok "マウントポイント作成: $PCLOUD_MOUNT"
fi
chmod 700 "$PCLOUD_MOUNT"

# pCloud リモート設定の確認
if rclone listremotes 2>/dev/null | grep -q '^pcloud:'; then
  ok "rclone pcloud リモート設定済み"
else
  fail "pCloud リモート未設定  →  OAuth 認証が必要です"
  echo "       手順: docs/pcloud-rclone-setup.md を参照してください"
  echo "       rclone config → n → 名前: pcloud → type: pcloud → OAuth 認証"
fi

# rclone.conf パーミッション確認
RCLONE_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/rclone/rclone.conf"
if [[ -f "$RCLONE_CONF" ]]; then
  chmod 600 "$RCLONE_CONF"
  ok "rclone.conf パーミッション確認 (600)"
fi

# ~/.profile への自動マウント設定
PROFILE="$HOME/.profile"
MOUNT_SNIPPET='
# pCloud マウント (rclone)
if command -v rclone >/dev/null 2>&1 && rclone listremotes 2>/dev/null | grep -q '"'"'^pcloud:'"'"'; then
  if ! mountpoint -q "$HOME/pcloud" 2>/dev/null && ! grep -qs " $HOME/pcloud " /proc/mounts; then
    rclone mount pcloud: "$HOME/pcloud" --vfs-cache-mode writes --daemon --log-level ERROR
  fi
fi'
MOUNT_MARKER='# pCloud マウント (rclone)'

if [[ -f "$PROFILE" ]] && grep -q "$MOUNT_MARKER" "$PROFILE"; then
  ok "~/.profile pCloud 自動マウント (設定済み)"
else
  echo "$MOUNT_SNIPPET" >> "$PROFILE"
  ok "~/.profile pCloud 自動マウント追加"
fi

echo "  ℹ  アンマウント: fusermount -u $PCLOUD_MOUNT"
