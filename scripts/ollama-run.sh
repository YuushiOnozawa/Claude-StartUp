#!/usr/bin/env bash
# scripts/ollama-run.sh <MODEL>
# ローカルLLM 統一実行ラッパー: stale lock チェック + flock 排他制御
# stdin からプロンプトを読む（pipe / redirect 両対応）
#
# 使用法: printf '%s' "$PROMPT" | bash ollama-run.sh <model>
#       または: bash ollama-run.sh <model> < prompt.txt
#
# 環境変数:
#   OLLAMA_LOCK_DIR  ロックファイルのディレクトリ（デフォルト: /tmp）

set -euo pipefail

MODEL="${1:?Usage: $(basename "$0") <model>}"
LOCK="${OLLAMA_LOCK_DIR:-/tmp}/ollama.lock"

# stale lock チェック（Ollama プロセスが存在しない場合はロックを解放）
[ -f "$LOCK" ] && ! pgrep -x ollama > /dev/null 2>&1 && rm -f "$LOCK"

# 排他ロック取得（タイムアウトなし・stale lock チェックで安全性を担保）
# stdin を flock 経由で ollama に渡す
exec flock "$LOCK" ollama run "$MODEL"
