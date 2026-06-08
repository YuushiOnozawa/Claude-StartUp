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
    return 0
  fi

  # lean-ctx hook rewrite（Bash コマンドを lean-ctx -c でラップ）は RTK と競合するため除去
  # RTK が先に Bash を書き換えるが、lean-ctx がさらに wrap すると lean-ctx の allowlist で RTK がブロックされる
  _settings="$HOME/.claude/settings.json"
  if [[ -f "$_settings" ]] && python3 -c "
import json, sys
with open('$_settings') as f: d = json.load(f)
pre = d.get('hooks', {}).get('PreToolUse', [])
filtered = [h for h in pre if not any('lean-ctx hook rewrite' in e.get('command','') for e in h.get('hooks',[]))]
if len(filtered) < len(pre):
    d['hooks']['PreToolUse'] = filtered
    with open('$_settings', 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
    ok "lean-ctx hook rewrite を除去（RTK 競合回避）"
  fi
fi
