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

# ~/.profile の既存スニペットを削除（移行後の冪等処理）
PROFILE="$HOME/.profile"
MOUNT_MARKER='# pCloud マウント (rclone)'
if [[ -f "$PROFILE" ]] && grep -q "$MOUNT_MARKER" "$PROFILE"; then
  # マーカー行から次の空行までを削除
  sed -i "/^${MOUNT_MARKER}/,/^$/d" "$PROFILE"
  ok "~/.profile 旧スニペット削除"
fi

# --- systemd ユーザーサービスへ移行 ---

# WSL2 systemd 有効化確認
WSL_CONF="/etc/wsl.conf"
SYSTEMD_ENABLED=false
if grep -qs '^\s*systemd\s*=\s*true' "$WSL_CONF" 2>/dev/null; then
  SYSTEMD_ENABLED=true
else
  echo "  → /etc/wsl.conf に systemd=true が未設定。自動追記します..."
  if ! grep -qs '^\[boot\]' "$WSL_CONF" 2>/dev/null; then
    printf '\n[boot]\nsystemd=true\n' | sudo tee -a "$WSL_CONF" >/dev/null
  else
    sudo sed -i '/^\[boot\]/a systemd=true' "$WSL_CONF"
  fi
  ok "/etc/wsl.conf に systemd=true を追記"
  echo "  ⚠  WSL を再起動してください: PowerShell で 'wsl --shutdown' を実行後、再度 setup.sh を実行"
  echo "     再起動後に systemd ユーザーサービスが有効になります"
  SYSTEMD_ENABLED=false
fi

# systemd ユーザーサービスのセットアップ
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/rclone-pcloud.service"
mkdir -p "$SERVICE_DIR"

cat > "$SERVICE_FILE" <<'SERVICE'
[Unit]
Description=rclone pCloud mount
After=network.target
AssertPathIsDirectory=%h/pcloud

[Service]
Type=notify
ExecStart=rclone mount pcloud: %h/pcloud --vfs-cache-mode writes --log-level ERROR
ExecStop=fusermount -u %h/pcloud
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SERVICE

ok "systemd サービスファイル生成: $SERVICE_FILE"

if $SYSTEMD_ENABLED && systemctl --user is-system-running &>/dev/null; then
  systemctl --user daemon-reload
  systemctl --user enable --now rclone-pcloud
  ok "rclone-pcloud サービス: 有効化・起動完了"
  echo "  ℹ  状態確認: systemctl --user status rclone-pcloud"
  echo "  ℹ  アンマウント: systemctl --user stop rclone-pcloud"
else
  echo "  ℹ  WSL 再起動後に以下を実行してサービスを有効化してください:"
  echo "     systemctl --user enable --now rclone-pcloud"
fi
