# DEV-FLOW-FAST — Phase Detail Reference

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
- If already on a non-`main`/`master` branch: set `$WORKTREE_PATH` to the absolute path of the current working directory (`$(pwd)`), then skip (worktree already active, proceed to Phase 4).
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

`references/codex-review.md` を Read し、記載の手順に従って Codex 敵対的レビューを実行する。
入力は `$DIFF`(Phase 4 で取得済みのdiff、または再取得)。

結果として `$BLOCK_COUNT` / `$MANUAL_COUNT` / `$WAIVED_COUNT` / `$FINDINGS` を受け取る。

初回のレビュー実行前に `$REVIEW_ITERATION=1` と初期化する。指摘の修正または waiver 判断後に `references/codex-review.md` を再実行するたび、再実行前に `$REVIEW_ITERATION=$((REVIEW_ITERATION+1))` と加算する。加算後に `$REVIEW_ITERATION -gt 5`（6回目、上限超過）ならレビューを実行せず `REVIEW_ESCALATE` とする。

```bash
# 初回レビューの直前に一度だけ実行
REVIEW_ITERATION=1

# 修正または waiver 判断の後、再レビューの直前に実行
REVIEW_ITERATION=$((REVIEW_ITERATION + 1))
if [ "$REVIEW_ITERATION" -gt 5 ]; then
  REVIEW_ESCALATE=1
fi
```

### `CODEX_REVIEW_FAILED` の場合
Codex companionが利用不可、または呼び出し・検証に失敗した場合。ローカルLLM(MAGI/BALTHASAR)への自動フォールバックはしない。以下を表示して停止する:
「⚠ Codexレビューが利用できないため、このルートを続行できません。理由: <エラー内容>。通常の /dev-flow (MAGI-FASTレビュー) をご利用ください。」

### `REVIEW_ESCALATE` の場合
最大反復回数(5回)に到達、または同一findingが解決後も再発する、または反復間でdiffが実質進展しない場合。自動LGTMを出さず停止し、「/magi-hard または人手レビューへの切替」をユーザーに提示する。

### `$BLOCK_COUNT = 0` かつ(`$MANUAL_COUNT = 0` または残る manual が全て waiver 済み)の場合
判定は `$WAIVED_COUNT > 0` なら `PASS_WITH_WAIVER`、それ以外は通常のLGTM。いずれの場合もPhase 6へ進む。`PASS_WITH_WAIVER`の場合、Phase 7のPR本文にwaiverしたfindingごとのID・根拠・影響範囲・判断者(ユーザー)を明記する。

### `$BLOCK_COUNT ≥ 1`、または未waiverの `manual` が残る場合
指摘一覧(`$FINDINGS`、defer含む)を提示する。各指摘には`persona`フィールド（MELCHIOR/BALTHASAR/CASPER/METATRON/SANDALPHON/LELIELのいずれか、Codexによる事後分類タグ）が含まれるため、提示時に併記する。

- `block`指摘: 修正内容を提示し、ユーザー承認後 `/codegen` で修正する。
- `manual`指摘: 自動`/codegen`修正対象にはしない。ユーザーに個別提示し、`AskUserQuestion`で選択を求める(finding単位、一括不可):
  - 「修正する」→ 修正方針をユーザーと合意し `/codegen` で修正
  - 「リスクを許容して進める(waiver)」→ このfindingを `waived` としてマークする(対象findingのbody内容とdiffハッシュに紐付ける。以後の再実行で対象コード領域のdiffが変わっていたらwaiverを無効化し再確認を求める)
  - waiverの選択は常にユーザーが行う。Codex/codegenはwaiverを選べない
- `defer`指摘は表示のみで、ループの継続条件には一切影響しない。

修正または waiver 判断の後、次回の `references/codex-review.md` 実行前に必ず `$DIFF` を空にする（`unset DIFF` または `DIFF=""`）。これにより次回のレビューは worktree の最新状態から diff を再取得し、Phase 4 で取得した `$DIFF` をそのまま再利用しない。
修正または waiver 判断の後、上記の `$REVIEW_ITERATION` 加算と上限判定を行ってから `references/codex-review.md` を再実行する。反復は最大5回。5回以内でも同一findingが解決後に再発する、または反復間でdiffが実質進展しない場合は `REVIEW_ESCALATE` とし、5回を超えて `$BLOCK_COUNT ≥ 1` または未waiver `manual` が残る場合も同様に扱う。

## Phase 6: COMMIT

Execute `/commit`.

## Phase 7: PR Creation

1. Push to remote:

```bash
BRANCH_NAME=$(git -C "$WORKTREE_PATH" branch --show-current)
git -C "$WORKTREE_PATH" push -u origin "$BRANCH_NAME"
```

2. Create PR (generate title and body from changes):

```bash
PR_URL=$(cd "$WORKTREE_PATH" && cat <<'EOF' | gh pr create --title "<type>(<scope>): <日本語タイトル>" --body-file -
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
`$WAIVED_COUNT > 0`の場合、PR本文にwaiver一覧(finding ID・根拠・影響範囲・判断者)を追記する。

> Worktree の掃除は merge 完了後に `/worktree done <branch>` を実行してください。
