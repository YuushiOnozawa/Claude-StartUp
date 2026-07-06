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

latest=$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1)
[[ -n "$latest" ]] || exit 1

# 直近 5 分以内に更新されていなければ現セッションと見なさない（誤爆防止）
[[ -n $(find "$latest" -mmin -5 2>/dev/null) ]] || exit 1

basename "$latest" .jsonl
