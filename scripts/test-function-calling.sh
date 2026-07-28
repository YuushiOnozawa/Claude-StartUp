#!/usr/bin/env bash
# scripts/test-function-calling.sh
# Ollama の function calling 動作確認スクリプト
#
# 使用法: bash scripts/test-function-calling.sh [MODE] [PR_NUM]
#   MODE    "native"  = /api/chat + tools パラメータ
#           "text"    = /api/generate + プロンプト内 JSON 指示（全モデル対応）
#           デフォルト: "text"
#   PR_NUM  ツール呼び出しに使う PR 番号（デフォルト: 181）
#
# 終了コード: 0=全員 OK, 1=一部失敗, 2=エラー

set -euo pipefail

MODE="${1:-text}"
PR_NUM="${2:-181}"
TIMEOUT="${OLLAMA_TIMEOUT:-300}"

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_OLLAMA_SH="$_SCRIPT_DIR/../hooks/lib/ollama.sh"
# shellcheck source=../hooks/lib/ollama.sh
[[ -f "$_OLLAMA_SH" ]] || { echo "Error: ollama.sh not found: $_OLLAMA_SH" >&2; exit 1; }
source "$_OLLAMA_SH"
OLLAMA_BASE_URL="$(ollama_base_url)"

OLLAMA_TAGS_JSON=""
if ! OLLAMA_TAGS_JSON="$(curl -sf --max-time 5 "${OLLAMA_BASE_URL}/api/tags" 2>/dev/null)"; then
  echo "SKIP: Ollama is not running. Skipping function calling test."
  exit 0
fi
OLLAMA_MODELS="$(printf '%s' "$OLLAMA_TAGS_JSON" | jq -r '.models[]?.name' 2>/dev/null || true)"

# CASPER は Ollama を使わず Haiku を標準モデルとするため含めない（skills/casper/SKILL.md）
# METATRON は Ollama を使わず Codex を標準モデルとするため含めない（skills/metatron/SKILL.md）
declare -A PERSONAS=(
  [melchior]="qwen2.5-coder:7b"
  [balthasar]="gemma4:e4b-it-qat"
  [sandalphon]="granite3.3:8b"
  [leliel]="lfm2.5:8b"
)

echo "=== MAGI function calling 検証 (mode: $MODE) ==="
echo ""

PASS=0; FAIL=0; SKIP=0

test_native() {
  local model="$1"
  local payload
  payload=$(jq -n --arg model "$model" --arg pr_num "$PR_NUM" \
    '{"model":$model,"messages":[{"role":"user","content":"Review PR #\($pr_num). Use get_pr_diff tool first."}],"tools":[{"type":"function","function":{"name":"get_pr_diff","description":"Get PR diff","parameters":{"type":"object","properties":{"pr_number":{"type":"integer"}},"required":["pr_number"]}}}],"stream":false}')
  local resp
  resp=$(curl -s --max-time "$TIMEOUT" "${OLLAMA_BASE_URL}/api/chat" \
    -H 'Content-Type: application/json' -d "$payload")
  local err tool_count
  err=$(printf '%s' "$resp" | jq -r '.error // empty')
  if [ -n "$err" ]; then echo "❌ error: $err"; return 1; fi
  tool_count=$(printf '%s' "$resp" | jq '.message.tool_calls // [] | length')
  if [ "$tool_count" -gt 0 ]; then
    local fn_name fn_args
    fn_name=$(printf '%s' "$resp" | jq -r '.message.tool_calls[0].function.name')
    fn_args=$(printf '%s' "$resp" | jq -r '.message.tool_calls[0].function.arguments | tostring')
    echo "✅ tool_calls[$tool_count]: $fn_name($fn_args)"
    return 0
  else
    local content
    content=$(printf '%s' "$resp" | jq -r '.message.content // "" | .[0:80]')
    echo "❌ tool_calls なし: $content"
    return 1
  fi
}

test_text() {
  local model="$1"
  local prompt
  prompt=$(cat <<'EOF'
You have access to the following tool. When you need to call it, output ONLY a JSON object with no other text:
{"name": "<tool_name>", "arguments": {<args>}}

Tool:
  get_pr_diff(pr_number: integer) - Get the git diff for a pull request

Task: I need to review PR #__PR__ for issues. Call the get_pr_diff tool to retrieve the diff.
EOF
)
  prompt="${prompt//__PR__/$PR_NUM}"
  local resp
  resp=$(curl -s --max-time "$TIMEOUT" "${OLLAMA_BASE_URL}/api/generate" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg model "$model" --arg prompt "$prompt" \
      '{"model":$model,"prompt":$prompt,"stream":false}')" \
    | jq -r '.response // empty' \
    | perl -0777 -pe 's/<think>.*?<\/think>\n?//gs')

  if [ -z "$resp" ]; then echo "❌ 空レスポンス"; return 1; fi

  # JSON ツール呼び出しを抽出（最初の {...} ブロック）
  local json_call
  json_call=$(printf '%s' "$resp" | grep -o '{[^{}]*}' | head -1 || true)
  if [ -n "$json_call" ]; then
    local fn_name fn_args
    fn_name=$(printf '%s' "$json_call" | jq -r '.name // empty' 2>/dev/null || true)
    fn_args=$(printf '%s' "$json_call" | jq -r '.arguments // {} | tostring' 2>/dev/null || true)
    if [ -n "$fn_name" ]; then
      echo "✅ JSON tool call: $fn_name($fn_args)"
      return 0
    fi
  fi
  echo "❌ JSON tool call なし: $(printf '%s' "$resp" | head -2 | tr '\n' ' ' | cut -c1-80)"
  return 1
}

for persona in "${!PERSONAS[@]}"; do
  model="${PERSONAS[$persona]}"
  printf "%-12s %-25s " "[$persona]" "$model"

  if ! printf '%s\n' "$OLLAMA_MODELS" | grep -Fxq -- "$model"; then
    echo "SKIP: model not found"
    ((SKIP++)) || true
    continue
  fi

  if [ "$MODE" = "native" ]; then
    if test_native "$model"; then ((PASS++)) || true
    else ((FAIL++)) || true; fi
  else
    if test_text "$model"; then ((PASS++)) || true
    else ((FAIL++)) || true; fi
  fi
done

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL SKIP=$SKIP ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
