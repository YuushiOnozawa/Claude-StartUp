# setup/500-pcloud.sh — pCloud FUSE マウント (pcloudcc) セットアップ
# Requires: ok, fail, ensure_local_bin_in_path, MISSING_CMDS (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- pCloud (pcloudcc) ---"

if command -v pcloudcc &>/dev/null; then
  ok "pcloudcc"
else
  echo "  → pcloudcc が未導入。ソースからビルドします..."

  # ビルド依存のチェックとインストール
  APT_DEPS=(cmake zlib1g-dev libboost-system-dev libfuse-dev libfuse2t64 git)
  MISSING_APT=()
  for dep in "${APT_DEPS[@]}"; do
    dpkg -s "$dep" &>/dev/null || MISSING_APT+=("$dep")
  done

  if [[ ${#MISSING_APT[@]} -gt 0 ]]; then
    echo "  → apt パッケージをインストール: ${MISSING_APT[*]}"
    if sudo apt-get install -y "${MISSING_APT[@]}" >/dev/null 2>&1; then
      ok "apt 依存パッケージ (インストール完了)"
    else
      fail "pcloudcc ビルド依存  →  手動: sudo apt-get install -y ${APT_DEPS[*]}"
      MISSING_CMDS+=("pcloudcc")
      return 0
    fi
  else
    ok "apt 依存パッケージ (インストール済み)"
  fi

  # ソースからビルド
  PCLOUD_TMP="$(mktemp -d)" || true
  if [[ -z "$PCLOUD_TMP" || ! -d "$PCLOUD_TMP" ]]; then
    fail "pcloudcc  →  一時ディレクトリの作成に失敗しました"
    MISSING_CMDS+=("pcloudcc")
    return 0
  fi

  PCLOUD_BIN="$HOME/.local/bin/pcloudcc"
  mkdir -p "$HOME/.local/bin"
  # バイナリのコピーもサブシェル内で行う（trap で PCLOUD_TMP が削除される前に）
  if (
    trap 'rm -rf "$PCLOUD_TMP"' EXIT
    git clone --depth 1 https://github.com/pCloud/console-client.git "$PCLOUD_TMP" &&
    cd "$PCLOUD_TMP/pCloudCC/lib/pclsync" && { make clean 2>/dev/null; true; } &&
    cd "$PCLOUD_TMP/pCloudCC/lib/mbedtls" && cmake . -DCMAKE_BUILD_TYPE=Release && make &&
    cd "$PCLOUD_TMP/pCloudCC" && cmake . && make &&
    BUILT_BIN="$(find "$PCLOUD_TMP/pCloudCC" -maxdepth 2 -name pcloudcc -type f | head -1)" &&
    [[ -n "$BUILT_BIN" ]] &&
    cp "$BUILT_BIN" "$PCLOUD_BIN" &&
    chmod +x "$PCLOUD_BIN"
  ); then
    ensure_local_bin_in_path
    ok "pcloudcc (ビルド・インストール完了: $PCLOUD_BIN)"
  else
    fail "pcloudcc  →  手動ビルド: https://github.com/pCloud/console-client"
    MISSING_CMDS+=("pcloudcc")
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

# 使い方ヒント
echo "  ℹ  初回マウント: pcloudcc -u YOUR_EMAIL -p -m $PCLOUD_MOUNT"
echo "  ℹ  Vault ファイルは $PCLOUD_MOUNT/<Vault名>/ に配置されます"
