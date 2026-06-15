#!/usr/bin/env bash
# unified diff をファイル単位に分割する
# 使用法: printf '%s' "$DIFF" | bash scripts/magi-split-diff.sh
# 出力: 各ファイルを "=== FILE: <path> ===" ヘッダーで区切ったセクション

awk '
/^diff --git / {
  if (buf != "") { print sep buf }
  path = $NF; sub(/^b\//, "", path)
  sep = "=== FILE: " path " ===\n"
  buf = $0 "\n"
  next
}
{ buf = buf $0 "\n" }
END { if (buf != "") print sep buf }
'
