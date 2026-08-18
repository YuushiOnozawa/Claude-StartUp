#!/usr/bin/env bash
# scripts/ollama-run.sh <MODEL> [SYSTEM_FILE]
# ローカルLLM 統一実行ラッパー: stale lock チェック + flock 排他制御
# stdin からプロンプトを読む（pipe / redirect 両対応）
#
# 使用法: bash ollama-run.sh <model> < prompt.txt
#       または: bash ollama-run.sh <model> system.txt < prompt.txt
#       または: bash ollama-run.sh --unload <model>
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
#   OLLAMA_NUM_PREDICT  生成トークン数上限（デフォルト: 4096）
#                       正の整数以外を指定した場合は警告を出して 4096 にフォールバックする。
#   OLLAMA_TEMPERATURE  サンプリング温度（デフォルト: 0.1）
#   OLLAMA_REPEAT_PENALTY  繰り返しペナルティ（デフォルト: 1.15）
#   OLLAMA_KEEP_ALIVE   モデル保持時間（デフォルト: 0 = 即時解放）
#                       例: OLLAMA_KEEP_ALIVE=5m bash ollama-run.sh <model> < prompt.txt
#                       duration 文字列（5m, 30s など）を指定するとモデルを保持する。
#                       無期限保持を避けるため、負値は受け付けない。
#                       無効値は警告を出して 0 にフォールバックする。
#   OLLAMA_RUN_LOG      生成実行ログファイル（デフォルト: /tmp/ollama-run.log）
#   OLLAMA_BASE_URL     Ollama ベース URL（デフォルト: WSL2 は自動検出、それ以外は http://localhost:11434）
#                       例: OLLAMA_BASE_URL=http://172.17.96.1:11434 bash ollama-run.sh <model>
#
# num_predict 上限で応答が切り詰められた場合は終了コード 75 で終了する。

set -euo pipefail

# hooks/lib/ollama.sh を source して Windows Ollama 対応の ollama_base_url() を使う
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_OLLAMA_SH="$_SCRIPT_DIR/../hooks/lib/ollama.sh"
# shellcheck source=../hooks/lib/ollama.sh
[[ -f "$_OLLAMA_SH" ]] || { echo "Error: ollama.sh not found: $_OLLAMA_SH" >&2; exit 1; }
source "$_OLLAMA_SH"
OLLAMA_URL="$(ollama_base_url)/api/generate"
LOCK="${OLLAMA_LOCK_DIR:-/tmp}/ollama.lock"

# モデルアンロード用ヘルパー（keep_alive:0 で使用後即時解放）
_unload_model() {
  [[ -n "${MODEL:-}" ]] || return 0
  local unload_json
  unload_json="$(jq -n --arg model "$MODEL" '{"model":$model,"keep_alive":0}')"
  curl -sf --max-time 10 "$OLLAMA_URL" \
    -H 'Content-Type: application/json' \
    -d "$unload_json" >/dev/null 2>&1
}

_log_line() {
  local log="${OLLAMA_RUN_LOG:-/tmp/ollama-run.log}"
  mkdir -p "$(dirname "$log")" 2>/dev/null || true
  printf '%s\n' "$*" >> "$log" 2>/dev/null || true
}

if [[ "${1:-}" == "--unload" ]]; then
  MODEL="${2:?Usage: $(basename "$0") --unload <model>}"
  mkdir -p "$(dirname "$LOCK")"
  exec 9>"$LOCK"
  if ! flock -w 5 9; then
    echo "Warning: could not acquire Ollama lock within 5s; unloading without lock" >&2
  fi
  if ! _unload_model; then
    echo "Warning: unload request failed for model: $MODEL" >&2
  fi
  exec 9>&- 2>/dev/null || true
  exit 0
fi

MODEL="${1:?Usage: $(basename "$0") <model> [system_file]}"
TIMEOUT="${OLLAMA_TIMEOUT:-1800}"
CONTEXT_SIZE="${OLLAMA_NUM_CTX:-16384}"
TEMPERATURE="${OLLAMA_TEMPERATURE:-0.1}"
REPEAT_PENALTY="${OLLAMA_REPEAT_PENALTY:-1.15}"
KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-0}"
if [[ -v OLLAMA_KEEP_ALIVE && -z "$OLLAMA_KEEP_ALIVE" ]]; then
  echo "Warning: invalid OLLAMA_KEEP_ALIVE value: empty string (falling back to 0)" >&2
  KEEP_ALIVE_JSON=0
elif [[ "$KEEP_ALIVE" =~ ^[0-9]+$ ]]; then
  KEEP_ALIVE_JSON="$(jq -n --arg v "$KEEP_ALIVE" '$v|tonumber')"
elif [[ "$KEEP_ALIVE" =~ ^[0-9]+(\.[0-9]+)?(ns|us|ms|s|m|h)$ ]]; then
  KEEP_ALIVE_JSON="$(jq -n --arg v "$KEEP_ALIVE" '$v')"
else
  echo "Warning: invalid OLLAMA_KEEP_ALIVE value: $KEEP_ALIVE (negative values mean indefinite retention and are not accepted; falling back to 0)" >&2
  KEEP_ALIVE_JSON=0
fi
NUM_PREDICT="${OLLAMA_NUM_PREDICT:-4096}"
if [[ -v OLLAMA_NUM_PREDICT && "$OLLAMA_NUM_PREDICT" =~ ^[1-9][0-9]*$ ]]; then
  NUM_PREDICT="$OLLAMA_NUM_PREDICT"
elif [[ -v OLLAMA_NUM_PREDICT ]]; then
  echo "Warning: invalid OLLAMA_NUM_PREDICT value: $OLLAMA_NUM_PREDICT (falling back to 4096)" >&2
  NUM_PREDICT=4096
fi

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

# シグナルハンドリング: curl kill → モデルアンロード → ロック解放
_CURL_PID=""
_RESP=""
_CLEANED_UP=0
_cleanup() {
  local _reason="${1:-exit}"
  [[ "$_CLEANED_UP" -eq 1 ]] && return 0
  _CLEANED_UP=1
  if [[ -n "${_CURL_PID:-}" ]]; then
    kill "$_CURL_PID" 2>/dev/null || true
    wait "$_CURL_PID" 2>/dev/null || true
    _CURL_PID=""
  fi
  if [[ "$_reason" == "signal" ]] || [[ "$_reason" == "exit" && "$KEEP_ALIVE_JSON" == "0" ]]; then
    if [[ -n "${MODEL:-}" ]]; then
      _unload_model || true
    fi
  fi
  exec 9>&- 2>/dev/null || true
  [[ -n "${_RESP:-}" ]] && rm -f "$_RESP" || true
}
trap '_cleanup signal; trap - EXIT; exit 130' INT
trap '_cleanup signal; trap - EXIT; exit 143' TERM
trap '_cleanup exit' EXIT

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
_LOG_START_EPOCH="$(date +%s)"
_log_line "$(date '+%Y-%m-%d %H:%M:%S')"$'\t'"$MODEL"$'\t'"$$"

if [[ -n "$SYSTEM" ]]; then
  JSON="$(jq -n \
    --arg model "$MODEL" \
    --arg system "$SYSTEM" \
    --arg prompt "$PROMPT" \
    --argjson num_ctx "$CONTEXT_SIZE" \
    --argjson temperature "$TEMPERATURE" \
    --argjson num_predict "$NUM_PREDICT" \
    --argjson repeat_penalty "$REPEAT_PENALTY" \
    --argjson keep_alive "$KEEP_ALIVE_JSON" \
    '{"model":$model,"system":$system,"prompt":$prompt,"stream":false,"keep_alive":$keep_alive,"options":{"num_ctx":$num_ctx,"temperature":$temperature,"num_predict":$num_predict,"repeat_penalty":$repeat_penalty}}')"
else
  JSON="$(jq -n \
    --arg model "$MODEL" \
    --arg prompt "$PROMPT" \
    --argjson num_ctx "$CONTEXT_SIZE" \
    --argjson temperature "$TEMPERATURE" \
    --argjson num_predict "$NUM_PREDICT" \
    --argjson repeat_penalty "$REPEAT_PENALTY" \
    --argjson keep_alive "$KEEP_ALIVE_JSON" \
    '{"model":$model,"prompt":$prompt,"stream":false,"keep_alive":$keep_alive,"options":{"num_ctx":$num_ctx,"temperature":$temperature,"num_predict":$num_predict,"repeat_penalty":$repeat_penalty}}')"
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

if [[ "$_curl_status" -ne 0 ]]; then
  _log_line "$(date '+%Y-%m-%d %H:%M:%S')"$'\t'"$MODEL"$'\t'"$(( $(date +%s) - _LOG_START_EPOCH ))"$'\t'"error:$_curl_status"
  exec 9>&-
  exit "$_curl_status"
fi

DONE_REASON="$(jq -r '.done_reason // empty' "$_RESP")"
if [[ "$DONE_REASON" == "length" ]]; then
  echo "Warning: Ollama response truncated at num_predict=$NUM_PREDICT tokens (done_reason=length)" >&2
  rm -f "$_RESP"
  _RESP=""
  _log_line "$(date '+%Y-%m-%d %H:%M:%S')"$'\t'"$MODEL"$'\t'"$(( $(date +%s) - _LOG_START_EPOCH ))"$'\t'"truncated"
  exec 9>&-
  exit 75
fi

jq -r '.response // empty' "$_RESP" \
  | perl -0777 -pe 's/<think>.*?<\/think>\n?//gs'
_log_line "$(date '+%Y-%m-%d %H:%M:%S')"$'\t'"$MODEL"$'\t'"$(( $(date +%s) - _LOG_START_EPOCH ))"$'\t'"ok"
exec 9>&-
rm -f "$_RESP"
_RESP=""
