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

## Phase 1.5: Design Review

`skills/flow-common/references/design-review.md` を Read し、以下の変数をセットして手順に従う。

- `PLAN_TEXT=$EPIC_PLAN`（必須）
- `REVIEW_TYPE="epic"`（文脈補助のみ）
- `REVIEW_CONTEXT=$CLARIFY_NOTES`（grill-me 結果があれば設定）

Hold `$DESIGN_REVIEW_RESULT` and `$DESIGN_REVIEW_SOURCE`. Proceed to Phase 2.

## Phase 2: CHECK ✋

Present the Epic plan and design review using the format below. Then **call `AskUserQuestion`** with:
- question: "[要件の 1〜2 行サマリー]\n\n### Feature 分解\n[分解内容]\n\n### 依存関係・実装順序\n[順序]\n\n### 設計レビュー（$DESIGN_REVIEW_SOURCE）\n$DESIGN_REVIEW_RESULT"
- options: ["承認（Issue作成・実装開始）", "修正（修正内容を続けて入力）", "中断"]

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

### 設計レビュー（$DESIGN_REVIEW_SOURCE）
$DESIGN_REVIEW_RESULT

```

On **修正**: return to Phase 1, revise, and re-run design-review.
On **承認**: call `ExitPlanMode`, then call `ctx_compress` to free context before implementation. Proceed to Phase 3.

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

**Call `AskUserQuestion`** with:
- question: "Issue #N: feat/<name> — [タイトル]\n\nこの Feature の実装に着手しますか？"
- options: ["着手（/dev-flow 開始）", "スキップ（次のIssueへ）", "終了（ループ中断）"]

### Execute /dev-flow

Execute `/dev-flow`, using the relevant Issue's content as the Phase 1 (PLAN) requirements.

> Design review inside dev-flow targets the plan (as normal).

### Stop after PR creation

After dev-flow Phase 7 (PR creation) completes, stop and present:

✓ Issue #N: PR 作成完了 → <PR URL>

**Call `AskUserQuestion`** with:
- question: "次の Feature に進みますか？（Issue #M: feat/<next-name>）"
- options: ["進む（Issue #M を開始）", "あとで（ここで終了 — 再開: /epic-flow #M）"]

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
