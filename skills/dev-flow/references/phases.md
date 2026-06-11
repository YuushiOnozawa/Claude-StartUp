# DEV-FLOW — Phase Detail Reference

## Phase 1: PLAN

### Step 0: CLARIFY（要件確認）

Analyze the user's request for design readiness.

**Skip if** the request already specifies target files, tech choices, or step-by-step requirements → proceed to plan creation below.

**Otherwise**, identify gaps from these areas and ask up to 5 questions. **Stop and wait for user input:**

```
## 設計前の確認事項 ✋

以下を教えてください（分かる範囲で構いません）：

1. [質問]
2. [質問]
...

0. このまま設計に進む
```

| Area | Examples |
|------|----------|
| Goal / Users | Who uses it? What problem does it solve? |
| Scope | What is in and out of scope? |
| Integration | What existing systems does it connect to? |
| Constraints | Tech stack, things that must not break, deadlines |
| Acceptance criteria | What does "done" look like? (✓/✗ format, test perspective) |

After answers (or if skipped / user chose 0): output a 1–2 line summary confirming understanding (or summarize the initial request). Hold as `$CLARIFY_NOTES`.

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

Present the plan and BALTHASAR review in the format below. **Stop here and wait for user input.**

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

---
承認しますか？
1. 承認 → ブランチ作成・実装開始
2. 修正: 〜 → プランを修正して再提示（BALTHASAR 再実行）
3. 中断
```

On **2** (修正): return to Phase 1, revise the plan, and re-run BALTHASAR.
On **1** (承認): call `ExitPlanMode`, then call `ctx_compress` to free context before implementation. Proceed to Phase 3.

## Phase 3: WORKTREE

Check current branch:
- If already on a non-`main`/`master` branch: skip (worktree already active, proceed to Phase 4).
- If on `main`/`master`: Execute `/worktree new <branch-name>`.
  - Branch name auto-generated from plan (English, kebab-case, `feat/` or `fix/` prefix).

After worktree creation, present the plan summary and instruct the user:

```
Worktree を作成しました: ./worktree/<branch>

以下のコマンドで新しいセッションを起動してください：
  cd ./worktree/<branch> && claude

新しいセッションで Phase 4 (IMPL) から続けてください。
このセッションは終了します。
```

**Stop here.** Implementation continues in the new session where CWD = worktree.

## Phase 4: IMPL

### Step 0: Write tests first (TDD)

Based on `$PLAN` **Test scenarios**, create test files before implementation.

- Confirm tests fail (Red) before starting implementation
- If tests cannot be written, record the reason in a code comment or commit message and skip

### Step 1: Implement

Execute `/codegen` with the approved plan. Claude writes the spec; Gemma4 implements.
Fall back to direct implementation only if Ollama is unavailable.

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
