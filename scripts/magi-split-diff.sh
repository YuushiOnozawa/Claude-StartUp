#!/usr/bin/env bash
# git unified diff をファイル単位に分割する（git diff 専用）
# 使用法: printf '%s' "$DIFF" | bash scripts/magi-split-diff.sh
# 出力: 各ファイルを "=== FILE: <path> ===" ヘッダーで区切ったセクション

awk '
/^diff --git a\// && / b\// {
  if (buf != "") { print sep buf }
  path = $NF; sub(/^b\//, "", path)  # b/ プレフィックスを除去（git diff b/<path> 形式専用）
  sep = "=== FILE: " path " ===\n"
  buf = $0 "\n"
  next
}
{ buf = buf $0 "\n" }
END { if (buf != "") print sep buf }
'
