#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DETECTOR="$REPO_ROOT/scripts/check-review-fast-no-post.sh"
FIXTURE="$REPO_ROOT/scripts/fixtures/review-dispatch-fast-with-post.md"
HARD_REUSE_FIXTURE="$REPO_ROOT/scripts/fixtures/review-dispatch-fast-with-hard-reuse-post.md"
HARD_REUSE_DOC="$REPO_ROOT/scripts/fixtures/codex-review-hard-reused-with-post.md"
PASS=0
FAIL=0

record_result() {
  if [[ "$2" -eq 0 ]]; then
    echo "PASS: $1"
    ((PASS++)) || true
  else
    echo "FAIL: $1"
    ((FAIL++)) || true
  fi
}

if "$DETECTOR" >/dev/null 2>&1; then result=0; else result=1; fi
record_result "review-fast の実ファスト分岐に投稿 edge がない" "$result"

if "$DETECTOR" --dispatch-file "$FIXTURE" >/dev/null 2>&1; then result=1; else result=0; fi
record_result "fast 分岐へ review-post を注入した負 fixture を検出する" "$result"

if "$DETECTOR" --dispatch-file "$HARD_REUSE_FIXTURE" --hard-reference "$HARD_REUSE_DOC" >/dev/null 2>&1; then result=1; else result=0; fi
record_result "fast が再利用する hard 節への review-post 注入を検出する" "$result"

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
[[ "$FAIL" -eq 0 ]]
