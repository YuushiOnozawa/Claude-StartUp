#!/usr/bin/env bash

# magi-impact-context.sh — $DIFF から呼び出し元スニペット付き $IMPACT_CONTEXT を生成する
# Usage: bash scripts/magi-impact-context.sh "$DIFF"
# 失敗時は空文字を出力して exit 0（中断しない）
#
# ツール選定: codegraph（MCP 経由のコールグラフ）を優先し、未インストール時は rg にフォールバック。
# ctags/cscope は動的に生成したインデックスの更新タイミングが不安定なため不採用。LSP は
# バックグラウンドサーバー起動を必要とし bash スクリプトからの呼び出しが困難なため不採用。

DIFF="${1:-}"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
MAX_CALLERS=10
CONTEXT_LINES=10

SYMBOLS=$(printf '%s\n' "$DIFF" \
  | grep '^+' | grep -v '^+++' \
  | grep -oP '(?<=(def |function |fn |const |let |var )\s{0,5})\w+' \
  | sort -u | head -20) || true

if [ -z "$SYMBOLS" ]; then
  exit 0
fi

OUTPUT=""
for SYMBOL in $SYMBOLS; do
  if command -v codegraph &>/dev/null; then
    CALLERS=$(codegraph --find-callers "$SYMBOL" --root "$REPO_ROOT" 2>/dev/null | head -"$MAX_CALLERS" || true)
  else
    CALLERS=$(rg -n --no-heading "$SYMBOL" "$REPO_ROOT" --glob '!*.md' --glob '!*.txt' 2>/dev/null | head -"$MAX_CALLERS" || true)
  fi

  if [ -z "$CALLERS" ]; then
    continue
  fi

  OUTPUT="${OUTPUT}### ${SYMBOL}"
  OUTPUT="${OUTPUT}"$'\n'
  while IFS= read -r LINE; do
    FILEPATH=$(printf '%s' "$LINE" | cut -d: -f1)
    LINENUM=$(printf '%s' "$LINE" | cut -d: -f2)

    if [ -f "$FILEPATH" ] && [[ "$LINENUM" =~ ^[0-9]+$ ]]; then
      START=$(( LINENUM > CONTEXT_LINES ? LINENUM - CONTEXT_LINES : 1 ))
      END=$(( LINENUM + CONTEXT_LINES ))
      SNIPPET=$(sed -n "${START},${END}p" "$FILEPATH" 2>/dev/null || true)
      OUTPUT="${OUTPUT}**${FILEPATH}:${LINENUM}**"
      OUTPUT="${OUTPUT}"$'\n'
      OUTPUT="${OUTPUT}\`\`\`"
      OUTPUT="${OUTPUT}"$'\n'
      OUTPUT="${OUTPUT}${SNIPPET}"
      OUTPUT="${OUTPUT}"$'\n'
      OUTPUT="${OUTPUT}\`\`\`"
      OUTPUT="${OUTPUT}"$'\n'
    fi
  done <<< "$CALLERS"
done

printf '%s' "$OUTPUT"
