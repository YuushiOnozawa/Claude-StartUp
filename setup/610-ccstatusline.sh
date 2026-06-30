# setup/610-ccstatusline.sh — ccstatusline のインストールと設定デプロイ
# Requires: ok, fail, MISSING_NPM (append-only), SETUP_DIR, check_package

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- ccstatusline ---"

# 1. パッケージの確認・インストール
check_package "ccstatusline" npm "ccstatusline"

# 2. ~/.local/bin にシンボリックリンクを作成
#    Claude Code の statusLine コマンドは mise が未 activate な環境で実行される場合があるため、
#    ~/.local/bin（PATH 恒久追加済み）経由で確実に参照できるようにする
_CCSL_SHIM="$HOME/.local/share/mise/shims/ccstatusline"
_CCSL_BIN="$HOME/.local/bin/ccstatusline"
mkdir -p "$HOME/.local/bin"
if [[ -f "$_CCSL_SHIM" ]]; then
  ln -sf "$_CCSL_SHIM" "$_CCSL_BIN"
  ok "ccstatusline シンボリックリンク作成 → $_CCSL_BIN"
else
  fail "mise シムが見つかりません: $_CCSL_SHIM（ccstatusline のインストールを確認してください）"
fi
unset _CCSL_SHIM _CCSL_BIN

# 3. 設定ファイルのデプロイ
_CCSL_SRC="$(dirname "$SETUP_DIR")/dotfiles/ccstatusline-settings.json"
_CCSL_DST_DIR="$HOME/.config/ccstatusline"
_CCSL_DST="$_CCSL_DST_DIR/settings.json"

mkdir -p "$_CCSL_DST_DIR"

if cp "$_CCSL_SRC" "$_CCSL_DST"; then
  ok "ccstatusline 設定をデプロイしました → $_CCSL_DST"
else
  fail "ccstatusline 設定のデプロイに失敗しました"
fi

unset _CCSL_SRC _CCSL_DST_DIR _CCSL_DST
