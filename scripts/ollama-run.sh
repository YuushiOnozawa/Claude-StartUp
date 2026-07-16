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
#   MAGI レビュー呼び出しで推奨: OLLAMA_REPEAT_PENALTY=1.3 OLLAMA_NUM_PREDICT=4096（#314 実測）
#   OLLAMA_BASE_URL     Ollama ベース URL（デフォルト: WSL2 は自動検出、それ以外は http://localhost:11434）
#                       例: OLLAMA_BASE_URL=http://172.17.96.1:11434 bash ollama-run.sh <model>
#   OLLAMA_THINK        think パラメータ（デフォルト: false で thinking chain を無効化）
#                       thinking chain が必要な場合は OLLAMA_THINK=true で上書き可能
#                       "false" のみ正式サポート。非対応モデルはこのパラメータを無視する。

set -euo pipefail

# hooks/lib/ollama.sh を source して Windows Ollama 対応の ollama_base_url() を使う
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_OLLAMA_SH="$_SCRIPT_DIR/../hooks/lib/ollama.sh"
# shellcheck source=../hooks/lib/ollama.sh
[[ -f "$_OLLAMA_SH" ]] || { echo "Error: ollama.sh not found: $_OLLAMA_SH" >&2; exit 1; }
source "$_OLLAMA_SH"
OLLAMA_URL="$(ollama_base_url)/api/generate"

MODEL="${1:?Usage: $(basename "$0") <model> [system_file]}"
LOCK="${OLLAMA_LOCK_DIR:-/tmp}/ollama.lock"
TIMEOUT="${OLLAMA_TIMEOUT:-1800}"
CONTEXT_SIZE="${OLLAMA_NUM_CTX:-16384}"
TEMPERATURE="${OLLAMA_TEMPERATURE:-0.1}"
REPEAT_PENALTY="${OLLAMA_REPEAT_PENALTY:-}"
NUM_PREDICT="${OLLAMA_NUM_PREDICT:-}"
THINK_OPT="${OLLAMA_THINK:-false}"

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

# モデルアンロード用ヘルパー（keep_alive:0 で使用後即時解放）
_unload_model() {
  [[ -n "${MODEL:-}" ]] || return 0
  local unload_json
  unload_json="$(jq -n --arg model "$MODEL" '{"model":$model,"keep_alive":0}')"
  curl -sf --max-time 10 "$OLLAMA_URL" \
    -H 'Content-Type: application/json' \
    -d "$unload_json" >/dev/null 2>&1 || true
}

# シグナルハンドリング: curl kill → モデルアンロード → ロック解放
_CURL_PID=""
_RESP=""
_CLEANED_UP=0
_cleanup() {
  [[ "$_CLEANED_UP" -eq 1 ]] && return 0
  _CLEANED_UP=1
  if [[ -n "${_CURL_PID:-}" ]]; then
    kill "$_CURL_PID" 2>/dev/null || true
    wait "$_CURL_PID" 2>/dev/null || true
    _CURL_PID=""
  fi
  [[ -n "${MODEL:-}" ]] && _unload_model
  exec 9>&- 2>/dev/null || true
  [[ -n "${_RESP:-}" ]] && rm -f "$_RESP" || true
}
trap '_cleanup; trap - EXIT; exit 130' INT
trap '_cleanup; trap - EXIT; exit 143' TERM
trap '_cleanup' EXIT

# stale lock チェック（flock ホルダープロセスが死んでいる場合はロックを解放）
# pgrep -x ollama では ollama サーバーの生死しか判定できず、flock ホルダーである
# シェルプロセスが異なる場合に stale lock を正しく検出できない。そのため lsof で
# ロックファイルを保持しているプロセスの PID を特定し kill -0 で生死を確認する。
# 注意: lsof チェック後 rm -f するまでの間に別プロセスがロックを取得する TOCTOU
# 競合状態が理論上存在するが、flock 自体が排他制御を担保するため実害は限定的。
if [ -f "$LOCK" ]; then
  LOCK_PID=$(lsof "$LOCK" 2>/dev/null | awk 'NR>1{print $2}' | head -1 || true)
  if [ -z "$LOCK_PID" ] || ! kill -0 "$LOCK_PID" 2>/dev/null; then
    rm -f "$LOCK"
  fi
fi

# 排他ロック取得（subshell なし: main shell で _CURL_PID を管理するため）
mkdir -p "$(dirname "$LOCK")"
exec 9>"$LOCK"
flock 9

if [[ -n "$SYSTEM" ]]; then
  JSON="$(jq -n \
    --arg model "$MODEL" \
    --arg system "$SYSTEM" \
    --arg prompt "$PROMPT" \
    --argjson num_ctx "$CONTEXT_SIZE" \
    --argjson temperature "$TEMPERATURE" \
    '{"model":$model,"system":$system,"prompt":$prompt,"stream":false,"keep_alive":0,"options":{"num_ctx":$num_ctx,"temperature":$temperature}}')"
else
  JSON="$(jq -n \
    --arg model "$MODEL" \
    --arg prompt "$PROMPT" \
    --argjson num_ctx "$CONTEXT_SIZE" \
    --argjson temperature "$TEMPERATURE" \
    '{"model":$model,"prompt":$prompt,"stream":false,"keep_alive":0,"options":{"num_ctx":$num_ctx,"temperature":$temperature}}')"
fi

if [[ -n "$REPEAT_PENALTY" ]]; then
  JSON="$(printf '%s\n' "$JSON" | jq --argjson repeat_penalty "$REPEAT_PENALTY" \
    '.options.repeat_penalty = $repeat_penalty')"
fi
if [[ -n "$NUM_PREDICT" ]]; then
  JSON="$(printf '%s\n' "$JSON" | jq --argjson num_predict "$NUM_PREDICT" \
    '.options.num_predict = $num_predict')"
fi

if [[ "$THINK_OPT" == "false" ]]; then
  JSON="$(printf '%s\n' "$JSON" | jq '. + {"think": false}')"
fi

_RESP="$(mktemp)"
curl -sf --max-time "$TIMEOUT" "$OLLAMA_URL" \
  -H 'Content-Type: application/json' \
  -d "$JSON" \
  -o "$_RESP" &
_CURL_PID=$!
_curl_status=0
wait "$_CURL_PID" || _curl_status=$?
_CURL_PID=""
exec 9>&-

if [[ "$_curl_status" -ne 0 ]]; then
  exit "$_curl_status"
fi

RAW_RESP="$(jq -r '.response // empty' "$_RESP")"
rm -f "$_RESP"
_RESP=""

# 未閉じ <think> 検出（think:false 非対応環境・他 reasoning model の安全弁）
if printf '%s' "$RAW_RESP" | grep -q '<think>' && \
   ! printf '%s' "$RAW_RESP" | grep -q '</think>'; then
  printf '⚠ <think> タグが未閉じで終了しました。OLLAMA_NUM_CTX=%s が不足している可能性があります。OLLAMA_NUM_CTX を増やして再実行してください。\n' \
    "$CONTEXT_SIZE" >&2
  exit 1
fi

printf '%s\n' "$RAW_RESP" | perl -0777 -pe 's/<think>.*?<\/think>\n?//gs'
