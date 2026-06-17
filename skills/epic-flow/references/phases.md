# EPIC-FLOW — Phase Detail Reference

> Phase 0 (SCALE ASSESSMENT) is handled in SKILL.md. Start here after confirming EPIC route.

## Phase 1: EPIC PLAN

### Step 0: GRILL-ME（要件深掘り）

**Skip if** the request already fully specifies target files, tech choices, and acceptance criteria → proceed to Step 1, holding the initial request summary as `$CLARIFY_NOTES`.

**Otherwise**, invoke `/grill-me` to conduct a deep-dive interview.

- grill-me は `AskUserQuestion` で一問ずつ、洞察が出なくなるまで深さ優先で掘り続ける
- 完了後に出力される「## まとめ / ### 決まったこと」を `$CLARIFY_NOTES` として保持する

---

### Step 1: Plan Creation

Call `EnterPlanMode`. Create an Epic design containing:

1. **Requirements** — what, why, for whom (incorporate `$CLARIFY_NOTES`)
2. **Feature decomposition** — split into independently releasable Feature units (numbered list)
   - Attach a `feat/<name>` branch name proposal to each Feature
   - State dependencies and recommended implementation order
3. **Overall architecture overview** — relationships between Features
4. **Risks / constraints** — shared prerequisites, caveats

Hold the design as `$EPIC_PLAN`. Proceed to Phase 1.5.

## Phase 1.5: BALTHASAR（Epic Design Review）

Execute BALTHASAR following the `/balthasar` skill steps 2–3, passing **`$EPIC_PLAN` as the review target**.

> Pass the Epic design text, not a diff. Instruction to BALTHASAR: 「以下の Epic 設計プランを設計・アーキテクチャ観点でレビューしてください」

Hold the result as `$BALTHASAR_EPIC_REVIEW`. Proceed to Phase 2.

## Phase 2: CHECK ✋

Present in the format below. **Stop here and wait for user input.**

```
## Epic 設計レビュー ✋

### 概要
[要件の 1〜2 行サマリー]

### Feature 分解
1. feat/<name-1> — [説明]（優先度: 高）
2. feat/<name-2> — [説明]（優先度: 中）
3. ...

### 依存関係・実装順序
[順序の理由]

---

### BALTHASAR レビュー（設計観点）
$BALTHASAR_EPIC_REVIEW

---
承認しますか？
1. 承認 → GitHub Issue 作成・フィーチャーループ開始
2. 修正: 〜 → 分解案を修正して再提示（BALTHASAR 再実行）
3. 中断
```

On **2** (修正): return to Phase 1, revise, and re-run BALTHASAR.
On **1** (承認): call `ExitPlanMode`, then call `ctx_compress` to free context before implementation. Proceed to Phase 3.

## Phase 3: ISSUE Creation

Create a GitHub Issue for each Feature:

```bash
ISSUE_URL=$(cat <<'EOF' | gh issue create \
  --title "feat(<name>): <日本語タイトル>" \
  --body-file -
## 概要
[Feature の説明]

## 実装内容
- ...

## 受け入れ条件
- [ ] ...
EOF
)
ISSUE_NUM=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$')
```

> **Note:** Properly quote `--title` if it contains special characters (`"`, `$`, backticks, etc.).

Append `$ISSUE_NUM` to `$ISSUE_LIST` (e.g., `ISSUE_LIST+=("$ISSUE_NUM")`). Repeat for all Features, then present the Issue list to the user.

## Phase 4: FEATURE LOOP

Process `$ISSUE_LIST` from the top, one at a time.

### Per-Feature start confirmation ✋

```
Issue #N: feat/<name> — [タイトル]

この Feature の実装に着手しますか？
1. 着手 → /dev-flow を開始
2. スキップ → 次の Issue へ
3. 終了 → ループを中断
```

### Execute /dev-flow

Execute `/dev-flow`, using the relevant Issue's content as the Phase 1 (PLAN) requirements.

> BALTHASAR review inside dev-flow targets the plan (as normal).

### Stop after PR creation

After dev-flow Phase 7 (PR creation) completes, stop and present:

```
✓ Issue #N: PR 作成完了 → <PR URL>

次の Feature に進みますか？
1. 進む → Issue #M: feat/<next-name> を開始
2. あとで → ここで終了（再開は /epic-flow #M で指定可）
```

### Loop completion

After all Issues are processed:

```
✓ Epic 完了。全 Feature の PR が作成されました。

作成された PR：
- #<PR番号> feat/<name-1>
- #<PR番号> feat/<name-2>
- ...

次のステップ：
- /pr-review-respond でレビュー対応
- /magi-hard で PR レビュー
```
