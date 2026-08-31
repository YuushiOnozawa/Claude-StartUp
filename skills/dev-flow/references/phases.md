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

## Phase 1.5: Design Review

`skills/flow-common/references/design-review.md` を Read し、以下の変数をセットして手順に従う。

- `PLAN_TEXT=$PLAN`（必須）
- `REVIEW_TYPE="feature"`（文脈補助のみ）
- `REVIEW_CONTEXT=$CLARIFY_NOTES`（grill-me 結果があれば設定）

Hold `$DESIGN_REVIEW_RESULT` and `$DESIGN_REVIEW_SOURCE`. Proceed to Phase 2.

## Phase 2: CHECK ✋

Present the plan and design review using the format below. Then **call `AskUserQuestion`** with:
- question: "[要件の 1〜2 行サマリー]\n\n[プラン内容]\n\n### 設計レビュー（$DESIGN_REVIEW_SOURCE）\n$DESIGN_REVIEW_RESULT"
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

### 設計レビュー（$DESIGN_REVIEW_SOURCE）
$DESIGN_REVIEW_RESULT

```

On **修正**: return to Phase 1, revise the plan, and re-run design-review.
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
> When executing `/commit` or `/review-fast`, apply this `-C $WORKTREE_PATH` override to all git commands within those skills.

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

### Fast backend と dispatch

1. backend は次の優先順で決める（明示的に渡された値を必ず使い、UI を出さない）:
   1. `$REVIEW_FAST_BACKEND_OVERRIDE` が `magi` または `codex` ならそれを使い、**当該 review 完了後に破棄する**。
   2. なければ `$REVIEW_FAST_BACKEND`（epic-flow から `ARGUMENTS` の `review fast backend=<magi|codex>` で
      渡された値を含む）が `magi` または `codex` ならそれを使う。
   3. どちらも未設定・不正なら `AskUserQuestion` を 1 回だけ呼び `$REVIEW_FAST_BACKEND` に設定する。
2. `review fast backend=<決定した backend>` を明示して `/review-fast` を実行し、返された envelope JSON のパスを `$REVIEW_DISPATCH_RESULT` として保持する。
3. 分岐には envelope の `dispatch_status`、`gate_decision`、`lgtm_eligible`、`manual_review_required`、`blocking_count`、`failure_reason` のキーだけを使い、backend 固有の生出力では分岐しない。
4. 修正ループ中は backend 選択 UI を再表示せず、PR 内では同じ backend を保持する。

### `complete` + `lgtm` → Phase 6

`$REVIEW_DISPATCH_RESULT` で次の条件をすべて満たすときだけ Phase 6 へ進む:
`dispatch_status == "complete"` ∧ `gate_decision == "lgtm"` ∧ `lgtm_eligible == true` ∧ `manual_review_required == false`.
これは Phase 6 への唯一の経路である。`lgtm_eligible != true` なら理由を問わず Phase 6 へ進まない。

### `complete` + `block`/`manual` → fix

`dispatch_status == "complete"` かつ `gate_decision` が `block` または `manual` のときだけ、既存どおり修正提案 → ユーザー判断 → 再実行のループへ入る。ブロック指摘の件数には envelope の `blocking_count` を使う。各 blocking finding の修正案を提示する。`manual`/`needs_human` は `/codegen` へ自動投入せず、ユーザーに判断を求める。修正後は同じ backend を明示して `/review-fast` を再実行し、Phase 6 の条件を満たすまで繰り返す。

### Catch-all: Fail-closed

上記の Phase 6 経路にも fix ループにも該当しないものは、理由を問わずすべて fail-closed とする。対象には
`dispatch_status != "complete"`、`gate_decision == "indeterminate"`、`dispatch_status == "complete"` だが
`lgtm_eligible != true` で、かつ `gate_decision` が `block` / `manual` でもない場合を含む。信頼できるゲート結果がないため
findings を修正対象にせず、`failure_reason` をユーザーに提示して `/review-hard` または手動レビューを推奨する。
LGTM は出さない。

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
