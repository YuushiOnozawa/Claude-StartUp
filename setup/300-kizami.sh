# setup/300-kizami.sh — kizami (長期記憶) セットアップ
# Requires: ok, fail, MISSING_CMDS (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

# npm 存在ガード (kizami ビルドに npm が必須)
if ! command -v npm &>/dev/null; then
  fail "kizami  →  npm が必要です（100-core.sh で未解決）"
  MISSING_CMDS+=("kizami")
  return 0
fi

# --- kizami (長期記憶): 会話履歴の自動保存・recall ---
if ! command -v pnpm &>/dev/null; then
  echo "  → pnpm が未導入。自動インストール: npm install -g pnpm"
  if npm install -g pnpm >/dev/null; then
    ok "pnpm (自動インストール完了)"
  else
    fail "pnpm  →  手動: npm install -g pnpm"
    MISSING_CMDS+=("pnpm")
  fi
fi

if ! command -v kizami &>/dev/null; then
  if ! command -v pnpm &>/dev/null; then
    fail "kizami  →  pnpm が必要です。先に pnpm をインストールしてください"
    MISSING_CMDS+=("kizami")
  else
    echo "  → kizami が未導入。一時ディレクトリで clone・ビルドします..."
    KIZAMI_TMP="$(mktemp -d)"
    if [[ -z "$KIZAMI_TMP" || ! -d "$KIZAMI_TMP" ]]; then
      fail "kizami  →  一時ディレクトリの作成に失敗しました"
      MISSING_CMDS+=("kizami")
    elif (
      trap 'rm -rf "$KIZAMI_TMP"' EXIT
      git clone https://github.com/okamyuji/kizami.git "$KIZAMI_TMP" &&
      cd "$KIZAMI_TMP" &&
      pnpm install &&
      pnpm add sqlite-vec @huggingface/transformers &&
      pnpm build &&
      pnpm pack --out kizami.tgz &&
      npm install -g "$KIZAMI_TMP/kizami.tgz"
    ); then
      ok "kizami (自動インストール完了)"
    else
      fail "kizami  →  手動: https://github.com/okamyuji/kizami"
      MISSING_CMDS+=("kizami")
    fi
  fi
else
  ok "kizami"
fi

# kizami のインストール確認と hybrid セットアップ
if command -v kizami &>/dev/null; then
  echo "  → kizami setup --hybrid で hook と DB を初期化..."
  if kizami setup --hybrid >/dev/null; then
    ok "kizami hybrid セットアップ完了"
  else
    fail "kizami setup 失敗  →  手動: kizami setup --hybrid"
    if [[ ! " ${MISSING_CMDS[*]} " =~ " kizami " ]]; then
      MISSING_CMDS+=("kizami")
    fi
  fi
else
  if [[ ! " ${MISSING_CMDS[*]} " =~ " kizami " ]]; then
    fail "kizami コマンドが PATH に見つかりません"
    MISSING_CMDS+=("kizami")
  fi
fi
