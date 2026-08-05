# setup/250-lean-ctx.sh — lean-ctx (コンテキスト圧縮) セットアップ
# Requires: ok, fail, check_package, MISSING_CMDS (append-only)

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
  if _lctx_msg=$(lean-ctx onboard 2>&1); then
    ok "lean-ctx onboard 完了"
  # 冪等実行時: 既存設定済みの場合は非ゼロ終了 + "lean-ctx is connected" を出力する
  elif echo "$_lctx_msg" | grep -q "lean-ctx is connected"; then
    ok "lean-ctx onboard 完了（既存設定を確認）"
  else
    fail "lean-ctx onboard 失敗  →  手動: lean-ctx onboard"
    [[ -n "$_lctx_msg" ]] && echo "$_lctx_msg" >&2
    MISSING_CMDS+=("lean-ctx-onboard")
  fi

  # shell allowlist を無効化（デフォルトの組み込みリストは kizami 等の自前フックコマンドを
  # ブロックするため、新規環境で SessionEnd/UserPromptSubmit hook が [BLOCKED] になる。
  # `lean-ctx config set shell_allowlist '[]'` は値を文字列 "[]" として書き込むバグがあるため使わない）
  _lctx_config="$HOME/.config/lean-ctx/config.toml"
  if command -v lean-ctx &>/dev/null; then
    mkdir -p "$(dirname "$_lctx_config")"
    if [[ ! -f "$_lctx_config" ]]; then
      printf 'shell_allowlist = []\n' > "$_lctx_config"
      ok "lean-ctx config (shell_allowlist 無効化)"
    elif ! grep -q '^shell_allowlist' "$_lctx_config"; then
      printf 'shell_allowlist = []\n' >> "$_lctx_config"
      ok "lean-ctx config (shell_allowlist 無効化)"
    else
      ok "lean-ctx config (shell_allowlist 設定済み)"
    fi
  fi

  # lean-ctx hook rewrite（Bash コマンドを lean-ctx -c でラップ）は RTK と競合するため除去
  # RTK が先に Bash を書き換えるが、lean-ctx がさらに wrap すると lean-ctx の allowlist で RTK がブロックされる
  # onboard 成否に依存せず実行（以前の onboard で書き込まれた hook が残存している場合に備える）
  _settings="$HOME/.claude/settings.json"
  if [[ -f "$_settings" ]] && python3 -c "
import json, sys, os
path = '$_settings'
with open(path) as f: d = json.load(f)
pre = d.get('hooks', {}).get('PreToolUse', [])
filtered = [h for h in pre if not any('lean-ctx hook rewrite' in e.get('command','') for e in h.get('hooks',[]))]
if len(filtered) < len(pre):
    d['hooks']['PreToolUse'] = filtered
    tmp = path + '.tmp'
    with open(tmp, 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
    os.replace(tmp, path)
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
    ok "lean-ctx hook rewrite を除去（RTK 競合回避）"
  fi
fi
