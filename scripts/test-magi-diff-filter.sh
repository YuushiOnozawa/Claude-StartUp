#!/usr/bin/env bash
# test-magi-diff-filter.sh — magi-diff-filter.sh の動作確認テスト

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/magi-diff-filter.sh"
PASS=0
FAIL=0

run_test() {
  local desc="$1"
  local input="$2"
  local expect_empty="$3"  # "true" = 出力が空であること、"false" = 出力があること

  local output
  output=$(printf '%s\n' "$input" | bash "$SCRIPT")

  if [ "$expect_empty" = "true" ]; then
    if [ -z "$output" ]; then
      echo "PASS: $desc"
      ((PASS++)) || true
    else
      echo "FAIL: $desc (expected empty, got: $output)"
      ((FAIL++)) || true
    fi
  else
    if [ -n "$output" ]; then
      echo "PASS: $desc"
      ((PASS++)) || true
    else
      echo "FAIL: $desc (expected output, got empty)"
      ((FAIL++)) || true
    fi
  fi
}

# --- フィルタされるべきファイル ---
run_test "SKILL.md を除外" \
  "diff --git a/skills/melchior/SKILL.md b/skills/melchior/SKILL.md
--- a/skills/melchior/SKILL.md
+++ b/skills/melchior/SKILL.md
@@ -1 +1 @@
+changed" \
  "true"

run_test "CLAUDE.md を除外" \
  "diff --git a/CLAUDE.md b/CLAUDE.md
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -1 +1 @@
+changed" \
  "true"

run_test "agents/*.md を除外" \
  "diff --git a/agents/melchior.md b/agents/melchior.md
--- a/agents/melchior.md
+++ b/agents/melchior.md
@@ -1 +1 @@
+changed" \
  "true"

run_test "references/*.md を除外" \
  "diff --git a/skills/magi-common/references/task-base.md b/skills/magi-common/references/task-base.md
--- a/skills/magi-common/references/task-base.md
+++ b/skills/magi-common/references/task-base.md
@@ -1 +1 @@
+changed" \
  "true"

# --- フィルタされないべきファイル ---
run_test "通常スクリプトは通過" \
  "diff --git a/scripts/magi-diff-filter.sh b/scripts/magi-diff-filter.sh
new file mode 100644
--- /dev/null
+++ b/scripts/magi-diff-filter.sh
@@ -0,0 +1 @@
+#!/usr/bin/env bash" \
  "false"

run_test "SKILL.md に似た名前（非 .md 末尾）は通過" \
  "diff --git a/scripts/SKILL.md.bak b/scripts/SKILL.md.bak
--- /dev/null
+++ b/scripts/SKILL.md.bak
@@ -0,0 +1 @@
+backup" \
  "false"

echo ""
echo "Results: ${PASS} PASS / ${FAIL} FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
