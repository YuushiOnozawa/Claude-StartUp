#!/usr/bin/env bash
# scripts/ollama-run.sh <MODEL> [SYSTEM_FILE]
# ローカルLLM 統一実行ラッパー: stale lock チェック + flock 排他制御
# stdin からプロンプトを読む（pipe / redirect 両対応）
#
# 使用法: bash ollama-run.sh <model> < prompt.txt
#       または: bash ollama-run.sh <model> system.txt < prompt.txt
#
# 引数:
#   $1  MODEL        Ollama モデル名（必須）
#   $2  SYSTEM_FILE  system プロンプトファイルパス（省略可）
#
# 環境変数:
#   OLLAMA_LOCK_DIR     ロックファイルのディレクトリ（デフォルト: /tmp）
#   OLLAMA_TIMEOUT      REST API タイムアウト秒数（デフォルト: 1800）
#   OLLAMA_NUM_CTX      コンテキストウィンドウサイズ（デフォルト: 16384）
#                       以前は 65536 だったが VRAM 8GB 環境で KV キャッシュが溢れ推論不能になるため
#                       16384 に変更。LELIEL など長い diff を扱う場合は環境変数で上書きすること。
#                       例: OLLAMA_NUM_CTX=65536 bash ollama-run.sh <model> system.txt < prompt.txt
#   OLLAMA_TEMPERATURE  サンプリング温度（デフォルト: 0.1）

set -euo pipefail

MODEL="${1:?Usage: $(basename "$0") <model> [system_file]}"
LOCK="${OLLAMA_LOCK_DIR:-/tmp}/ollama.lock"
TIMEOUT="${OLLAMA_TIMEOUT:-1800}"
CONTEXT_SIZE="${OLLAMA_NUM_CTX:-16384}"
TEMPERATURE="${OLLAMA_TEMPERATURE:-0.1}"

# system プロンプトファイルの読み込み（省略可）
SYSTEM_FILE="${2:-}"
SYSTEM=""
if [[ -n "$SYSTEM_FILE" ]]; then
  if [[ -f "$SYSTEM_FILE" ]]; then
    SYSTEM="$(cat "$SYSTEM_FILE")"
  else
    echo "Error: system file not found: $SYSTEM_FILE" >&2
    exit 1
  fi
fi

# stdin を先に読む（flock 取得前に行う）
PROMPT="$(cat)"

# stale lock チェック（flock ホルダープロセスが死んでいる場合はロックを解放）
# pgrep -x ollama では ollama サーバーの生死しか判定できず、flock ホルダーである
# シェルプロセスが異なる場合に stale lock を正しく検出できない。そのため lsof で
# ロックファイルを保持しているプロセスの PID を特定し kill -0 で生死を確認する。
# 注意: lsof チェック後 rm -f するまでの間に別プロセスがロックを取得する TOCTOU
# 競合状態が理論上存在するが、flock 自体が排他制御を担保するため実害は限定的。
if [ -f "$LOCK" ]; then
  LOCK_PID=$(lsof "$LOCK" 2>/dev/null | awk 'NR>1{print $2}' | head -1)
  if [ -z "$LOCK_PID" ] || ! kill -0 "$LOCK_PID" 2>/dev/null; then
    rm -f "$LOCK"
  fi
fi

# 排他ロック取得 + REST API 呼び出し
(
  flock 9
  if [[ -n "$SYSTEM" ]]; then
    JSON="$(jq -n \
      --arg model "$MODEL" \
      --arg system "$SYSTEM" \
      --arg prompt "$PROMPT" \
      --argjson num_ctx "$CONTEXT_SIZE" \
      --argjson temperature "$TEMPERATURE" \
      '{"model":$model,"system":$system,"prompt":$prompt,"stream":false,"options":{"num_ctx":$num_ctx,"temperature":$temperature}}')"
  else
    JSON="$(jq -n \
      --arg model "$MODEL" \
      --arg prompt "$PROMPT" \
      --argjson num_ctx "$CONTEXT_SIZE" \
      --argjson temperature "$TEMPERATURE" \
      '{"model":$model,"prompt":$prompt,"stream":false,"options":{"num_ctx":$num_ctx,"temperature":$temperature}}')"
  fi
  curl -s --max-time "$TIMEOUT" http://localhost:11434/api/generate \
    -H 'Content-Type: application/json' \
    -d "$JSON" \
  | jq -r '.response // empty' \
  | perl -0777 -pe 's/<think>.*?<\/think>\n?//gs'
) 9>"$LOCK"
