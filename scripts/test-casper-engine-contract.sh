#!/usr/bin/env bash
# scripts/test-casper-engine-contract.sh — CASPER engine 共通契約の参照テスト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE_REF="skills/flow-common/references/casper-engine.md"
PASS=0
FAIL=0

record_result() {
  local description="$1"
  local status="$2"
  if [[ "$status" -eq 0 ]]; then
    echo "PASS: $description"
    ((PASS++)) || true
  else
    echo "FAIL: $description"
    ((FAIL++)) || true
  fi
}

for file in \
  "$REPO_ROOT/skills/magi-fast/SKILL.md" \
  "$REPO_ROOT/skills/magi-hard/SKILL.md" \
  "$REPO_ROOT/skills/dev-flow-fast/references/codex-review-hard.md" \
  "$REPO_ROOT/skills/dev-flow-fast/references/codex-review-fast.md"; do
  if grep -Fq "$ENGINE_REF" "$file"; then
    record_result "$(realpath --relative-to="$REPO_ROOT" "$file") が CASPER engine 契約を参照する" 0
  else
    record_result "$(realpath --relative-to="$REPO_ROOT" "$file") が CASPER engine 契約を参照する" 1
  fi
done

FAST_FILE="$REPO_ROOT/skills/dev-flow-fast/references/codex-review-fast.md"
if grep -Eiq 'codex-review-hard\.md[^\n]*(hardの)?[[:space:]]*ステップ[[:space:]]*[679]' "$FAST_FILE"; then
  record_result "codex-review-fast.md に CASPER の hard ステップ番号参照が残っていない" 1
else
  record_result "codex-review-fast.md に CASPER の hard ステップ番号参照が残っていない" 0
fi

if grep -RFn --include='*' -- 'agents/casper.md' "$REPO_ROOT/skills" >/dev/null 2>&1; then
  record_result "skills/ 配下に agents/casper.md 参照が残っていない" 1
else
  record_result "skills/ 配下に agents/casper.md 参照が残っていない" 0
fi

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
