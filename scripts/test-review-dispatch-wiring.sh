#!/usr/bin/env bash
# scripts/test-review-dispatch-wiring.sh — review dispatch 接続の doc 検査
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DISPATCH_REF="$REPO_ROOT/skills/flow-common/references/review-dispatch.md"
FAST_SKILL="$REPO_ROOT/skills/review-fast/SKILL.md"
HARD_SKILL="$REPO_ROOT/skills/review-hard/SKILL.md"
DEV_PHASES="$REPO_ROOT/skills/dev-flow/references/phases.md"
PR_SKILL="$REPO_ROOT/skills/pr-review/SKILL.md"
EPIC_PHASES="$REPO_ROOT/skills/epic-flow/references/phases.md"
SKILLS_INDEX="$REPO_ROOT/SKILLS.md"

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

# 1. fast / hard の薄い入口が契約正本を参照する。
if [[ -f "$FAST_SKILL" ]] && grep -Fq -- "review-dispatch.md" "$FAST_SKILL" \
  && [[ -f "$HARD_SKILL" ]] && grep -Fq -- "review-dispatch.md" "$HARD_SKILL"; then
  result=0
else
  result=1
fi
record_result "review-fast と review-hard が存在し review-dispatch.md を参照する" "$result"

# 2. MAGI のゲート判定失敗は全面ブラックアウトとして写像する。
if grep -Eq -- "ゲート判定失敗.*failed.*indeterminate" "$DISPATCH_REF"; then
  result=0
else
  result=1
fi
record_result "fast の MAGI ゲート失敗を failed / indeterminate に写像する" "$result"

# 3. CASPER 単体失敗は incomplete かつ blocking_count=null とする。
if grep -Eq -- "CASPER 単体失敗.*incomplete.*null" "$DISPATCH_REF"; then
  result=0
else
  result=1
fi
record_result "CASPER 単体失敗を incomplete / blocking_count=null に写像する" "$result"

# 4. Codex の incomplete は dispatch_status=incomplete として保持する。
if grep -Eq -- "pipeline_status=incomplete[[:space:]]*\\|[[:space:]]*incomplete" "$DISPATCH_REF"; then
  result=0
else
  result=1
fi
record_result "Codex の pipeline_status=incomplete を incomplete に保持する" "$result"

# 5. Codex hard backend は review-post まで実行する。
if grep -Eq -- "codex[[:space:]]*\\|.*\/review-post" "$DISPATCH_REF"; then
  result=0
else
  result=1
fi
record_result "codex backend で /review-post を呼ぶ記述がある" "$result"

# 6. hard envelope の集計正本を review-post-result.json の .counts.block に固定する。
if grep -Eq -- "hard の集計正本.*review-post-result\\.json" "$DISPATCH_REF" \
  && grep -Fq -- "review-post-result.json の .counts.block" "$DISPATCH_REF"; then
  result=0
else
  result=1
fi
record_result "hard の集計正本を review-post-result.json の .counts.block に固定する" "$result"

# 7. dispatch envelope の絶対パスを返却変数へ渡す。
if grep -Fq -- '$REVIEW_DISPATCH_RESULT' "$DISPATCH_REF"; then
  result=0
else
  result=1
fi
record_result "REVIEW_DISPATCH_RESULT の返却契約が記載されている" "$result"

# 8. fast / hard の backend 状態変数を分離する。
if grep -Fq -- '$REVIEW_FAST_BACKEND' "$DISPATCH_REF" \
  && grep -Fq -- '$REVIEW_HARD_BACKEND' "$DISPATCH_REF"; then
  result=0
else
  result=1
fi
record_result "REVIEW_FAST_BACKEND と REVIEW_HARD_BACKEND を別変数で扱う" "$result"

# 9. dev-flow Phase 5 は review-fast の envelope 以外を fail-closed にする。
if grep -Fq -- "/review-fast" "$DEV_PHASES" \
  && grep -Fq -- 'dispatch_status != "complete"' "$DEV_PHASES"; then
  result=0
else
  result=1
fi
record_result "dev-flow Phase 5 が /review-fast を呼び dispatch_status 非complete を fail-closed にする" "$result"

# 10. PR review の hard 接続先を確認する。
if grep -Fq -- "/review-hard" "$PR_SKILL"; then
  result=0
else
  result=1
fi
record_result "pr-review が /review-hard を呼ぶ" "$result"

# 11. Epic の完了案内は review-hard を示し、magi-hard を固定しない。
LOOP_COMPLETION="$(sed -n '/^### Loop completion/,$p' "$EPIC_PHASES")"
if grep -Fq -- "/review-hard" <<<"$LOOP_COMPLETION" \
  && ! grep -Fq -- "/magi-hard" <<<"$LOOP_COMPLETION"; then
  result=0
else
  result=1
fi
record_result "epic-flow の Loop completion 案内が /review-hard を含み /magi-hard を含まない" "$result"

# 12. PR review の次アクション判定は dispatch の状態変数で行う。
if grep -Fq -- "blocking_count" "$PR_SKILL" \
  && grep -Fq -- "manual_review_required" "$PR_SKILL"; then
  result=0
else
  result=1
fi
record_result "pr-review の次アクション判定が blocking_count / manual_review_required ベースである" "$result"

# 13. スキル一覧の pr-review 行を review-hard 接続として記載する。
PR_REVIEW_ROW="$(grep -F -- '| `/pr-review` |' "$SKILLS_INDEX" || true)"
if [[ -n "$PR_REVIEW_ROW" ]] \
  && grep -Fq -- "review-hard" <<<"$PR_REVIEW_ROW" \
  && ! grep -Fq -- "magi-hard" <<<"$PR_REVIEW_ROW"; then
  result=0
else
  result=1
fi
record_result "SKILLS.md の /pr-review 行が review-hard 接続で magi-hard 固定でない" "$result"

# 14. 変更しない dev-flow-fast 配下に HEAD 比の差分がない。
if git -C "$REPO_ROOT" diff --quiet HEAD -- skills/dev-flow-fast/; then
  result=0
else
  result=1
fi
record_result "skills/dev-flow-fast/ 配下に HEAD 比の差分がない" "$result"

# 15. PR review の LGTM 判定は lgtm_eligible を正本にする。
if grep -Fq -- "lgtm_eligible" "$PR_SKILL"; then
  result=0
else
  result=1
fi
record_result "pr-review の LGTM 判定が lgtm_eligible を参照する" "$result"

# 16. hard gate_decision は whitelist 外を fail-closed にする。
if grep -Fq -- "whitelist" "$DISPATCH_REF" \
  && grep -Fq -- "未知" "$DISPATCH_REF" \
  && grep -Fq -- "failed" "$DISPATCH_REF"; then
  result=0
else
  result=1
fi
record_result "hard gate_decision の whitelist と未知値の failed 写像が記載されている" "$result"

# 17. hard の needs_human は manual_review_required へ写像する。
if grep -Fq -- "needs_human" "$DISPATCH_REF" \
  && grep -Fq -- "manual_review_required=true" "$DISPATCH_REF"; then
  result=0
else
  result=1
fi
record_result "hard の needs_human が manual_review_required=true に写像される" "$result"

# 18. hard backend は epic-flow のスコープ外である。
if ! grep -Fq -- '$REVIEW_HARD_BACKEND' "$EPIC_PHASES"; then
  result=0
else
  result=1
fi
record_result "epic-flow に REVIEW_HARD_BACKEND の設定記述がない" "$result"

# 19. pr-review の次アクション判定は post_failed を fail-closed にする。
if grep -Fq -- "post_failed" "$PR_SKILL"; then
  result=0
else
  result=1
fi
record_result "pr-review の次アクション判定が post_state=post_failed を扱う" "$result"

# 20. dev-flow Phase 5 は fast override を優先順位付きで扱う。
if grep -Fq -- '$REVIEW_FAST_BACKEND_OVERRIDE' "$DEV_PHASES"; then
  result=0
else
  result=1
fi
record_result "dev-flow Phase 5 が REVIEW_FAST_BACKEND_OVERRIDE の優先順位を持つ" "$result"

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
