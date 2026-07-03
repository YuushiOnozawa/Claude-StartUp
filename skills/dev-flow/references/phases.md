# DEV-FLOW — Phase Detail Reference

## Phase 1: PLAN

### Step 0: GRILL-ME（要件深掘り）

**Skip if** the request already fully specifies target files, tech choices, and acceptance criteria → proceed to Step 1, holding the initial request summary as `$CLARIFY_NOTES`.

**Otherwise**, invoke `/grill-me` to conduct a deep-dive interview.

- grill-me は `AskUserQuestion` で一問ずつ、洞察が出なくなるまで深さ優先で掘り続ける
- 完了後に出力される「## まとめ / ### 決まったこと」を `$CLARIFY_NOTES` として保持する

---

### Step 1: Plan Creation

Call `EnterPlanMode`. Create a design plan containing:

1. **Requirements** — what, why, for whom (incorporate `$CLARIFY_NOTES`)
2. **Spec summary** — bullet-point list of each feature and behavior
3. **Test scenarios** — acceptance test scenarios in natural language (✓/✗ format)
4. **Implementation approach** — architecture, technology choices, key design decisions
5. **Affected files** — files to create, modify, or delete
6. **Implementation steps** — numbered concrete steps
7. **Risks / constraints** — caveats, prerequisites

Hold the plan as `$PLAN`. Proceed to Phase 1.5.

## Phase 1.5: BALTHASAR（Design Review）

Execute BALTHASAR following the `/balthasar` skill steps 2–3, passing **`$PLAN` as the review target**.

> Pass the plan text, not a diff. Instruction to BALTHASAR: 「以下の設計プランを設計・アーキテクチャ観点でレビューしてください」

Hold the result as `$BALTHASAR_PLAN_REVIEW`. Proceed to Phase 2.

## Phase 2: CHECK ✋

Present the plan and BALTHASAR review using the format below. Then **call `AskUserQuestion`** with:
- question: "[要件の 1〜2 行サマリー]\n\n[プラン内容]\n\n### BALTHASAR レビュー（設計観点）\n$BALTHASAR_PLAN_REVIEW"
- options: ["承認（実装開始）", "修正（修正内容を続けて入力）", "中断"]

```
## 設計レビュー ✋

### 概要
[要件の 1〜2 行サマリー]

### 実装方針
[主要な設計決定]

### 影響ファイル
[ファイル一覧]

### 実装ステップ
1. ...
2. ...

---

### BALTHASAR レビュー（設計観点）
$BALTHASAR_PLAN_REVIEW

```

On **修正**: return to Phase 1, revise the plan, and re-run BALTHASAR.
On **承認**: call `ExitPlanMode`, then call `ctx_compress` to free context before implementation. Proceed to Phase 3.

## Phase 3: WORKTREE

Check current branch:
- If already on a non-`main`/`master` branch: skip (worktree already active, proceed to Phase 4).
- If on `main`/`master`: Execute `/worktree new <branch-name>`.
  - Branch name auto-generated from plan (English, kebab-case, `feat/` or `fix/` prefix).
  - Hold the returned path as `$WORKTREE_PATH`.

Proceed to Phase 4 in the **same session**.

## Phase 4: IMPL

> **Worktree context**: All git commands in Phase 4–7 use `git -C $WORKTREE_PATH`.
> File read/write operations use `$WORKTREE_PATH/` as the base path.
> Example: `git -C $WORKTREE_PATH status`, `git -C $WORKTREE_PATH diff`
> When executing `/commit` or `/magi-fast`, apply this `-C $WORKTREE_PATH` override to all git commands within those skills.

### Step 0: Write tests first (TDD)

Based on `$PLAN` **Test scenarios**, create test files before implementation.

- Confirm tests fail (Red) before starting implementation
- If tests cannot be written, record the reason in a code comment or commit message and skip

### Step 1: Implement

Execute `/codegen` with the approved plan. Claude writes the task description; Codex implements and writes files directly.
Fall back to direct implementation only if Codex is unavailable.

### Step 2: Verify

- Run `git status` to verify changed files
- Display a diff summary with `git diff`

Proceed to Phase 5.

## Phase 5: REVIEW → FIX Loop

Execute `/magi-fast`.

### If HIGH = 0 → proceed to Phase 6

### If HIGH ≥ 1 → fix

Present a fix proposal for each HIGH finding. The user decides whether to adopt. After fixes, re-run `/magi-fast`. Repeat until HIGH = 0.

## Phase 6: COMMIT

Execute `/commit`.

## Phase 7: PR Creation

1. Push to remote:

```bash
git push -u origin <branch>
```

2. Create PR (generate title and body from changes):

```bash
PR_URL=$(cat <<'EOF' | gh pr create --title "<type>(<scope>): <日本語タイトル>" --body-file -
## 概要
[変更内容の 1〜3 行サマリー]

## 変更点
- ...

## テスト
- [ ] ...

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)
```

3. Present `$PR_URL` to the user.

> Worktree の掃除は merge 完了後に `/worktree done <branch>` を実行してください。
