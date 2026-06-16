#!/usr/bin/env bash
# scripts/ollama-run.sh <MODEL>
# ローカルLLM 統一実行ラッパー: stale lock チェック + flock 排他制御
# stdin からプロンプトを読む（pipe / redirect 両対応）
#
# 使用法: printf '%s' "$PROMPT" | bash ollama-run.sh <model>
#       または: bash ollama-run.sh <model> < prompt.txt
#
# 環境変数:
#   OLLAMA_LOCK_DIR     ロックファイルのディレクトリ（デフォルト: /tmp）
#   OLLAMA_TIMEOUT      REST API タイムアウト秒数（デフォルト: 1800）
#   OLLAMA_NUM_CTX      コンテキストウィンドウサイズ（デフォルト: 8192）
#   OLLAMA_TEMPERATURE  サンプリング温度（デフォルト: 0.1）

set -euo pipefail

MODEL="${1:?Usage: $(basename "$0") <model>}"
LOCK="${OLLAMA_LOCK_DIR:-/tmp}/ollama.lock"
TIMEOUT="${OLLAMA_TIMEOUT:-1800}"
NUM_CTX="${OLLAMA_NUM_CTX:-8192}"
TEMPERATURE="${OLLAMA_TEMPERATURE:-0.1}"

# stdin を先に読む（flock 取得前に行う）
PROMPT="$(cat)"

# stale lock チェック（Ollama プロセスが存在しない場合はロックを解放）
[ -f "$LOCK" ] && ! pgrep -x ollama > /dev/null 2>&1 && rm -f "$LOCK"

# 排他ロック取得 + REST API 呼び出し
(
  flock 9
  curl -s --max-time "$TIMEOUT" http://localhost:11434/api/generate \
    -H 'Content-Type: application/json' \
    -d "$(jq -n \
      --arg model "$MODEL" \
      --arg prompt "$PROMPT" \
      --argjson num_ctx "$NUM_CTX" \
      --argjson temperature "$TEMPERATURE" \
      '{"model":$model,"prompt":$prompt,"stream":false,"options":{"num_ctx":$num_ctx,"temperature":$temperature}}')" \
  | jq -r '.response // empty' \
  | perl -0777 -pe 's/<think>.*?<\/think>\n?//gs'
) 9>"$LOCK"
