#!/usr/bin/env bash
# magi-diff-filter.sh — git diff からロールプレイ指示ファイルを除外する
# Usage: printf '%s\n' "$DIFF" | bash scripts/magi-diff-filter.sh
#
# 除外対象: SKILL.md / CLAUDE.md / agents/*.md / references/*.md
awk -v excluded_list="${MAGI_FILTER_EXCLUDED_LIST:-}" '
BEGIN {
  fixture_path = "(^|/)tests?/fixtures?/"
  if (excluded_list != "") printf "%s", "" > excluded_list
}
/^diff --git/ {
  path = $NF
  sub(/^b\//, "", path)
  skip = ($0 ~ /SKILL\.md |CLAUDE\.md |\/agents\/.*\.md|\/references\/.*\.md/ || \
          (path ~ fixture_path \
              && path ~ /\.(json|jsonl|txt|patch|diff|csv|tsv|yml|yaml|xml)$/))
  if (skip && excluded_list != "" && path ~ fixture_path \
      && path ~ /\.(json|jsonl|txt|patch|diff|csv|tsv|yml|yaml|xml)$/) {
    print path > excluded_list
  }
}
!skip
'
