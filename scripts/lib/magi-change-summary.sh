#!/usr/bin/env bash
# magi-change-summary.sh — MAGI_CHANGE_SUMMARY の抽出・長さ制限ヘルパー
# Source this file, then call extract_pr_summary or truncate_utf8.

# PR 本文の Summary セクションから空行を除いた先頭2行を抽出する。
extract_pr_summary() {
  local pr_body="$1"

  printf '%s' "$pr_body" | awk '
    /^##[[:space:]]+Summary[[:space:]]*$/ {
      in_summary = 1
      next
    }
    /^##/ && in_summary {
      exit
    }
    in_summary && $0 !~ /^[[:space:]]*$/ {
      lines++
      if (lines <= 2) {
        print
      }
    }
  '
}

# UTF-8 の文字境界を保ったまま、指定 byte 数以内へ切り詰める。
truncate_utf8() {
  local text="$1"
  local max_bytes="${2:-300}"

  [[ "$max_bytes" =~ ^[0-9]+$ ]] || return 2
  head -c "$max_bytes" < <(printf '%s' "$text") | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null || true
}
