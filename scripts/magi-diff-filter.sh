#!/usr/bin/env bash
# magi-diff-filter.sh — git diff からロールプレイ指示ファイルを除外する
# Usage: printf '%s\n' "$DIFF" | bash scripts/magi-diff-filter.sh
#
# 除外対象: SKILL.md / CLAUDE.md / agents/*.md / references/*.md
awk '/^diff --git/{skip=($0 ~ /SKILL\.md |CLAUDE\.md |\/agents\/.*\.md|\/references\/.*\.md/)} !skip'
