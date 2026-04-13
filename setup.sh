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

check_npm_global() {
  local label="$1" pkg="$2" hint="$3"
  if npm list -g --depth=0 2>/dev/null | grep -q "$pkg"; then ok "$label"
  else fail "$label  →  $hint"; MISSING_NPM+=("$label"); fi
}

# ──────────────────────────────────────
# Step 1: clone
# ──────────────────────────────────────
echo "=== Step 1: リポジトリのセットアップ ==="
if [[ -n "$REPO_URL" ]]; then
  if [[ -d "$CLAUDE_DIR/.git" ]]; then
    echo "ℹ  $CLAUDE_DIR は既に git リポジトリです。clone をスキップ。"
  elif [[ -d "$CLAUDE_DIR" ]]; then
    # Claude Code インストール済みで ~/.claude が存在するが git 管理外の場合
    echo "→ $CLAUDE_DIR が存在します。git init して $REPO_URL を取得します..."
    git -C "$CLAUDE_DIR" init -q
    git -C "$CLAUDE_DIR" remote add origin "$REPO_URL"
    git -C "$CLAUDE_DIR" fetch origin
    default_branch="$(git -C "$CLAUDE_DIR" remote show origin | grep 'HEAD branch' | awk '{print $NF}')"
    if [[ -z "$default_branch" ]]; then
      echo "エラー: デフォルトブランチを取得できませんでした。"
      exit 1
    fi
    git -C "$CLAUDE_DIR" stash -q 2>/dev/null || true
    git -C "$CLAUDE_DIR" checkout "$default_branch"
    ok "セットアップ完了（ローカル変更は git stash に退避済み）"
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

# --- core ---
check_cmd "git"  "git"  "brew install git  /  apt install git"
check_cmd "node" "node" "https://nodejs.org/"
check_cmd "npm"  "npm"  "Node.js に同梱"

# --- git hooks / commit quality ---
if command -v npm &>/dev/null; then
  check_npm_global "commitlint" "@commitlint/cli" \
    "npm install -g @commitlint/cli @commitlint/config-conventional"
fi

# ── 将来のツール追加はここに追記 ──────────────────────────────
# check_cmd "gh"  "gh"  "brew install gh  /  https://cli.github.com/"
# check_cmd "jq"  "jq"  "brew install jq  /  apt install jq"
# check_npm_global "lefthook" "lefthook" "npm install -g lefthook"
# ──────────────────────────────────────────────────────────────

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
