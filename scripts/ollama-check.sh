#!/usr/bin/env bash
# scripts/ollama-check.sh <model> [<model>...]
# Ollama モデルの存在確認専用スクリプト
#
# 使用法:
#   bash ollama-check.sh <model> [<model>...]   指定モデルが利用可能か確認
#   bash ollama-check.sh                        引数なし: 利用可能なモデル一覧を表示
#
# 引数:
#   $@  MODEL...  確認したい Ollama モデル名（省略可、複数指定可）
#                 ":" なしで指定した場合は "<model>:latest" も一致とみなす
#
# 終了コード:
#   0  引数なし（一覧表示）、または指定モデルが全て存在
#   1  指定モデルのうち1つ以上が存在しない
#   2  Ollama サーバーに接続できない

set -euo pipefail

# hooks/lib/ollama.sh を source して Windows Ollama 対応の ollama_base_url() を使う
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_OLLAMA_SH="$_SCRIPT_DIR/../hooks/lib/ollama.sh"
# shellcheck source=../hooks/lib/ollama.sh
[[ -f "$_OLLAMA_SH" ]] || { echo "Error: ollama.sh not found: $_OLLAMA_SH" >&2; exit 1; }
source "$_OLLAMA_SH"

BASE_URL="$(ollama_base_url)"

TAGS_JSON="$(curl -sf --max-time 5 "${BASE_URL}/api/tags" 2>/dev/null || true)"
if [[ -z "$TAGS_JSON" ]]; then
  echo "✗ Ollama サーバーに接続できません（Windows 側で Ollama が起動しているか確認: ${BASE_URL}）" >&2
  exit 2
fi

# 引数なし: 利用可能なモデル一覧を表示
if [[ $# -eq 0 ]]; then
  echo "$TAGS_JSON" | jq -r '.models[].name'
  exit 0
fi

EXIT_CODE=0
for MODEL in "$@"; do
  if echo "$TAGS_JSON" | jq -r '.models[].name' | grep -qxF "$MODEL"; then
    echo "✓ $MODEL"
    continue
  fi
  if [[ "$MODEL" != *:* ]] && echo "$TAGS_JSON" | jq -r '.models[].name' | grep -qxF "${MODEL}:latest"; then
    echo "✓ $MODEL"
    continue
  fi
  echo "✗ $MODEL が見つかりません（Windows 側で \`ollama pull $MODEL\` を実行してください）" >&2
  EXIT_CODE=1
done

exit "$EXIT_CODE"
