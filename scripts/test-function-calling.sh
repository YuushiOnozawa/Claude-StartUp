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

declare -A PERSONAS=(
  [melchior]="qwen2.5-coder:7b"
  [balthasar]="phi4:latest"
  [casper]="llama3.1:8b"
  [metatron]="devstral:latest"
  [sandalphon]="lfm2.5:8b"
)

echo "=== MAGI function calling 検証 (mode: $MODE) ==="
echo ""

PASS=0; FAIL=0; SKIP=0

test_native() {
  local model="$1"
  local payload
  payload=$(printf '{"model":"%s","messages":[{"role":"user","content":"Review PR #%s. Use get_pr_diff tool first."}],"tools":[{"type":"function","function":{"name":"get_pr_diff","description":"Get PR diff","parameters":{"type":"object","properties":{"pr_number":{"type":"integer"}},"required":["pr_number"]}}}],"stream":false}' \
    "$model" "$PR_NUM")
  local resp
  resp=$(curl -s --max-time "$TIMEOUT" http://localhost:11434/api/chat \
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
  resp=$(curl -s --max-time "$TIMEOUT" http://localhost:11434/api/generate \
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

for persona in melchior balthasar casper metatron sandalphon; do
  model="${PERSONAS[$persona]}"
  printf "%-12s %-25s " "[$persona]" "$model"

  if ! ollama list 2>/dev/null | grep -q "^${model}"; then
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
