#!/usr/bin/env bash
# ~/.claude/setup.sh — 新マシンへの Claude Code ハーネス展開スクリプト
#
# 前提条件: Claude Code がインストール・認証済みであること
#
# 使い方:
#   bash setup.sh <repo-url>   # clone + 依存チェック
#   bash setup.sh              # clone なし・依存チェックのみ
#
set -euo pipefail

REPO_URL="${1:-}"
CLAUDE_DIR="$HOME/.claude"
MISSING_CMDS=()
MISSING_NPM=()

# ──────────────────────────────────────
# ヘルパー
# ──────────────────────────────────────
ok()   { echo "  ✓ $*"; }
fail() { echo "  ✗ $*"; }

check_cmd() {
  local label="$1" cmd="$2" hint="$3"
  if command -v "$cmd" &>/dev/null; then ok "$label"
  else fail "$label  →  $hint"; MISSING_CMDS+=("$label"); fi
}

# パッケージマネージャアダプタ (将来 pip/cargo 等を足すときはここに 3 関数追加)
npm_is_installed() {
  # npm list -g に複数パッケージを渡すと片方欠損でも exit 0 を返すバージョンがあるため、1 つずつ確認する
  local pkg
  for pkg in "$@"; do
    npm list -g "$pkg" --depth=0 >/dev/null 2>&1 || return 1
  done
}
npm_install()       { npm install -g "$@"; }
npm_install_hint()  { echo "npm install -g $*"; }

# ~/.local/bin を PATH に恒久追加 (冪等)
ensure_local_bin_in_path() {
  local local_bin="$HOME/.local/bin"
  local rc
  case "$(basename "${SHELL:-/bin/bash}")" in
    zsh)  rc="$HOME/.zshrc" ;;
    bash) rc="$HOME/.bashrc" ;;
    *)    rc="$HOME/.profile" ;;
  esac
  # rc への永続化: 現 PATH に通っているかに関わらず、マーカー未記録なら必ず書き込む
  if ! { [[ -f "$rc" ]] && grep -q 'Claude-StartUp: local bin' "$rc"; }; then
    {
      echo ''
      echo '# Claude-StartUp: local bin (RTK 等)'
      echo 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac'
    } >> "$rc"
    echo "  ℹ  $rc に ~/.local/bin 用の PATH 追加を書き込みました (次回シェル起動から恒久有効)"
  fi
  # 現セッションの PATH 補完 (重複防止)
  case ":$PATH:" in
    *":$local_bin:"*) ;;
    *) export PATH="$local_bin:$PATH" ;;
  esac
}

check_package() {
  local label="$1" pm="$2"
  shift 2
  local pkgs=("$@")
  local check_fn="${pm}_is_installed"
  local install_fn="${pm}_install"
  local hint_fn="${pm}_install_hint"

  if "$check_fn" "${pkgs[@]}"; then
    ok "$label"
    return
  fi
  echo "  → $label が未導入。自動インストール実行: $("$hint_fn" "${pkgs[@]}")"
  if "$install_fn" "${pkgs[@]}" >/dev/null; then
    ok "$label (自動インストール完了)"
  else
    fail "$label  →  手動で実行: $("$hint_fn" "${pkgs[@]}")"
    MISSING_NPM+=("$label")
  fi
}

# ──────────────────────────────────────
# Step 1: clone
# ──────────────────────────────────────
echo "=== Step 1: リポジトリのセットアップ ==="
if [[ -n "$REPO_URL" ]]; then
  if ! command -v git &>/dev/null; then
    echo "エラー: git が見つかりません。リポジトリ取得には git が必要です。" >&2
    echo "先に git をインストールしてから再実行してください。" >&2
    exit 1
  fi
  if [[ -d "$CLAUDE_DIR/.git" ]]; then
    echo "ℹ  $CLAUDE_DIR は既に git リポジトリです。clone をスキップ。"
  elif [[ -d "$CLAUDE_DIR" ]]; then
    # Claude Code インストール済みで ~/.claude が存在するが git 管理外の場合
    echo "→ $CLAUDE_DIR が存在します。git init して $REPO_URL を取得します..."
    git -C "$CLAUDE_DIR" init -q
    git -C "$CLAUDE_DIR" remote add origin "$REPO_URL"
    default_branch="$(git -C "$CLAUDE_DIR" ls-remote --symref origin HEAD | awk '/^ref:/ {sub(/refs\/heads\//, "", $2); print $2; exit}')" || true
    if [[ -z "$default_branch" ]]; then
      echo "エラー: デフォルトブランチを取得できませんでした。"
      exit 1
    fi
    git -C "$CLAUDE_DIR" fetch origin

    # checkout は既存ファイルを無警告で上書きしうるため、衝突するファイルがあれば先に停止させる
    conflicts=()
    while IFS= read -r f; do
      [[ -e "$CLAUDE_DIR/$f" ]] && conflicts+=("$f")
    done < <(git -C "$CLAUDE_DIR" ls-tree -r --name-only "origin/$default_branch")
    if (( ${#conflicts[@]} > 0 )); then
      echo "エラー: 以下の既存ファイルがリポジトリのファイルと衝突します:"
      printf '  - %s\n' "${conflicts[@]}"
      echo "  $CLAUDE_DIR のバックアップを取ってから再実行してください。"
      exit 1
    fi

    git -C "$CLAUDE_DIR" checkout "$default_branch"
    ok "セットアップ完了"
  else
    echo "→ $REPO_URL を $CLAUDE_DIR に clone 中..."
    git clone "$REPO_URL" "$CLAUDE_DIR"
    ok "clone 完了"
  fi
else
  echo "ℹ  repo URL 未指定。clone をスキップ。"
fi

# ──────────────────────────────────────
# Step 2: 依存ツールチェック
# ──────────────────────────────────────
echo ""
echo "=== Step 2: 依存ツールの確認 ==="

# setup/ 内の *.sh を番号プレフィックス順で自動検出・実行
# 新ツール追加時: setup/NNN-xxx.sh を作成するだけ（setup.sh の編集不要）
SETUP_DIR="$CLAUDE_DIR/setup"
[[ -d "$SETUP_DIR" ]] || { echo "ERROR: $SETUP_DIR が見つかりません" >&2; exit 1; }
shopt -u nullglob  # glob 不一致時にリテラル文字列が返るよう保証
for mod in "$SETUP_DIR"/*.sh; do
  [[ -f "$mod" ]] || { echo "ERROR: $SETUP_DIR にモジュールが見つかりません" >&2; exit 1; }
  source "$mod"
done

# ──────────────────────────────────────
# サマリー
# ──────────────────────────────────────
echo ""
echo "=== 結果 ==="
ALL_MISSING=()
[[ ${#MISSING_CMDS[@]} -gt 0 ]] && ALL_MISSING+=("${MISSING_CMDS[@]}")
[[ ${#MISSING_NPM[@]} -gt 0 ]]  && ALL_MISSING+=("${MISSING_NPM[@]}")

if [[ ${#ALL_MISSING[@]} -gt 0 ]]; then
  echo "⚠  不足: ${ALL_MISSING[*]}"
  echo "   上記をインストールしてから再実行してください。"
  exit 1
else
  echo "✓ 依存ツールはすべて揃っています。セットアップ完了です。"
fi
