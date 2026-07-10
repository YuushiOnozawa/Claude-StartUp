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

### 3-0. State ファイルの定義と初期化

```bash
EPIC_STATE_FILE="$(git rev-parse --git-common-dir)/epic-state.md"
```

- `--git-common-dir` により main チェックアウトでも worktree でも同一パスに解決される
- セッション横断で永続。mktemp は使わない
- **1リポジトリ 1 アクティブ Epic 前提（並行実行は非サポート）**

state ファイルが**存在しない場合のみ**、以下のブロック形式で初期化する（全体書き直し）:

```markdown
# Epic State
status: active
epic: <Epic の概要 1 行（人間・LLM の確認用）>

## Feature 1
branch: feat/<name1>
title: <タイトル1>
issue: —
status: planned
pr: —

## Feature 2
branch: feat/<name2>
title: <タイトル2>
issue: —
status: planned
pr: —
```

state が存在する場合は Phase 4 冒頭「再開手順」が先に処理しているため、ここには到達しない。

### 3-1. Issue 作成ループ（state-first + marker 方式）

各 Feature について以下の **A → B → C** の順で処理する:

**ステップ A: state に issue 番号が記録済み？**
- `issue:` フィールドが番号（`—` 以外）→ **スキップ**（重複作成防止）

**ステップ B: marker 検索（クラッシュ回収）**

List API + ローカル grep でインデックス遅延を回避:

```bash
gh issue list --state all --json number,body \
  | jq -r '.[] | select(.body | contains("epic-branch: feat/<name>")) | .number' \
  | head -1
```

- ヒットした → その番号を state に記録（全体書き直し）して**スキップ**

**ステップ C: Issue 作成**

Issue 本文末尾に以下の HTML コメントを必ず含める:

```
<!-- epic-branch: feat/<name> -->
```

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

<!-- epic-branch: feat/<name> -->
EOF
)
ISSUE_NUM=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$')
```

`gh issue create` 成功直後に state 全体書き直し（`issue:` フィールドに `$ISSUE_NUM` を記録）。

ループ完了後、Issue リストをユーザーに提示。

## Phase 4: FEATURE LOOP

### 再開手順

```bash
EPIC_STATE_FILE="$(git rev-parse --git-common-dir)/epic-state.md"
```

state ファイルの状態に応じて以下の3分岐で処理する:

**分岐 1: ファイルが存在しない かつ 引数 `#M` 指定あり**
→ 停止。ユーザーに「state ファイルが見つかりません」と報告（Phase 3 への自動再作成なし）

**分岐 2: `status: completed`**
→ 「この Epic は完了済み」と表示し state の内容（epic / Feature 一覧）を提示。
新規 Epic 開始を確認 → 開始する場合は旧 state を `epic-state-<YYYYMMDD>.md` にリネームして退避
→ SCALE ASSESSMENT（SKILL.md Phase 0）に戻る

**分岐 3: `status: active`**
→ state の `epic:` フィールドを読み取り、AskUserQuestion で確認:
  question: "アクティブな Epic が見つかりました（`<epic フィールドの内容>`）。続きから再開しますか？"
  options: ["再開（続きから）", "新規開始（state を退避して新しい Epic を開始）"]
  「新規開始」の場合: 旧 state を `epic-state-<YYYYMMDD>.md` にリネームして退避 → SCALE ASSESSMENT（SKILL.md Phase 0）に戻る
→ state を Read して Feature 一覧・status / PR URL を復元
→ 引数 `#M` が指定されている場合: state の全 Feature の `issue:` 番号と照合する。
  `#M` が存在しない → 停止し state の内容（epic / Feature 一覧）をユーザーに提示して確認
→ `in_progress` の Feature がある場合:
  `git branch` と `gh pr list` で該当ブランチ・PR の実在を確認し、
  `AskUserQuestion` で「続きから dev-flow 再開 / done 扱いにする / skip する」を選択させる
→ `planned` / `in_progress` の Feature から FEATURE LOOP を開始

---

### Per-Feature start confirmation ✋

**Call `AskUserQuestion`** with:
- question: "Issue #N: feat/<name> — [タイトル]\n\nこの Feature の実装に着手しますか？"
- options: ["着手（/dev-flow 開始）", "スキップ（次のIssueへ）", "終了（ループ中断）"]

**状態遷移（全体書き直しで更新）:**

| タイミング | 遷移 |
|---|---|
| 「着手」選択 | `planned` → `in_progress`（全体書き直し） |
| 「スキップ」選択 | `planned` → `skipped`（全体書き直し） |

### Execute /dev-flow

Execute `/dev-flow`, using the relevant Issue's content as the Phase 1 (PLAN) requirements.

> Design review inside dev-flow targets the plan (as normal).

### Stop after PR creation

After dev-flow Phase 7 (PR creation) completes:

1. state 全体書き直し（当該 Feature を `done` + PR URL に更新）— **ctx_compress より必ず先**
2. `ctx_compress` を呼ぶ
3. 次 Feature 着手確認（`AskUserQuestion`）

present:

✓ Issue #N: PR 作成完了 → <PR URL>

**Call `AskUserQuestion`** with:
- question: "次の Feature に進みますか？（Issue #M: feat/<next-name>）"
- options: ["進む（Issue #M を開始）", "あとで（ここで終了 — 再開: /epic-flow #M）"]

### Loop completion

全 Feature が `done` / `skipped` になったら:

1. state 全体書き直し（`status: completed` に更新）
2. `Epic 状態ファイル: $EPIC_STATE_FILE` をユーザーに表示

✓ Epic 完了。全 Feature の PR が作成されました。

- #<PR番号> feat/<name-1>
- #<PR番号> feat/<name-2>

次のステップ:
- /pr-review-respond でレビュー対応
- /magi-hard で PR レビュー

> state ファイルは削除しない（次の Epic 開始時に退避して世代管理）
