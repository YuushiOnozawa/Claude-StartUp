#!/bin/bash
# 現在のセッション ID を推定する。
# 仕組み: ~/.claude/projects/<slug>/ 内で直近に更新された .jsonl の basename が
# 現セッションの session_id である可能性が高い。
# Hard gate: 5 分以内に更新された transcript がなければ何も出力せず exit 1。
set -uo pipefail

cwd=$(pwd)
# slug 変換規則: / と . を - に置換（実物で確認済み）
slug=$(printf '%s' "$cwd" | sed 's/[\/.]/-/g')
dir="$HOME/.claude/projects/$slug"
[[ -d "$dir" ]] || exit 1

# glob 展開を避け find + mtime ソートで最新 .jsonl を取得
latest=$(find "$dir" -maxdepth 1 -type f -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null \
  | sort -nr | head -1 | cut -d' ' -f2-)
[[ -n "$latest" ]] || exit 1

# 直近 N 分以内に更新されていなければ現セッションと見なさない（誤爆防止）
# CLAUDE_SESSION_TIMEOUT 環境変数で上書き可能（デフォルト 5 分）
SESSION_TIMEOUT="${CLAUDE_SESSION_TIMEOUT:-5}"
[[ "${SESSION_TIMEOUT}" =~ ^[1-9][0-9]*$ ]] || SESSION_TIMEOUT=5
[[ -n $(find "$latest" -mmin -"$SESSION_TIMEOUT" 2>/dev/null) ]] || exit 1

basename "$latest" .jsonl
