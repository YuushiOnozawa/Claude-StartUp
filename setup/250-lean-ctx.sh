# setup/250-lean-ctx.sh — lean-ctx (コンテキスト圧縮) セットアップ
# Requires: ok, fail, check_package, MISSING_NPM (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

# npm 存在ガード
if ! command -v npm &>/dev/null; then
  fail "lean-ctx  →  npm が必要です（100-core.sh で未解決）"
  MISSING_CMDS+=("lean-ctx")
  return 0
fi

# lean-ctx-bin インストール
check_package "lean-ctx" npm lean-ctx-bin

# onboard: MCP 登録・フック・CLAUDE.md ルール追記（冪等）
if command -v lean-ctx &>/dev/null; then
  echo "  → lean-ctx onboard を実行（冪等）..."
  if lean-ctx onboard 2>/dev/null; then
    ok "lean-ctx onboard 完了"
  else
    fail "lean-ctx onboard 失敗  →  手動: lean-ctx onboard"
    MISSING_CMDS+=("lean-ctx-onboard")
  fi
fi
