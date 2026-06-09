---
name: epic-flow
desc: 要件の規模を自動判断し、単一機能なら /dev-flow へ、複数機能なら GitHub Issue に分解してフィーチャーループを回す。Trigger: "/epic-flow", "epic-flow", "〜を作りたい", "〜を実装したい", "〜機能を追加したい", "〜を追加して", "〜を作って"
---

# EPIC-FLOW スキル

要件の規模を判断し、適切なワークフローにルーティングする。

---

## フェーズ 0: SCALE ASSESSMENT（規模判定）

ユーザーの要件を聞いて、以下の基準で規模を判断する：

| 規模 | 主判定軸 | 補助 | ルーティング |
|------|---------|------|------------|
| **DEV** | 独立した PR が 1 つで完結する | 影響ファイル 1〜3 件 | `/dev-flow` に委譲 |
| **EPIC** | 独立した PR が複数想定される | 影響ファイル 4 件以上 | EPIC フローを続行 |

**曖昧な場合：** 1 文で確認する（「単一機能として進めますか、機能分解しますか？」）

### DEV ルート

`/dev-flow` スキルをそのまま実行する。以降の EPIC フェーズには進まない。

### EPIC ルート

フェーズ 1 に進む。

---

## フェーズ 1: EPIC PLAN（機能分解）

`EnterPlanMode` を呼び出し、以下を含む Epic 設計を作成する：

1. **要件整理** — 何を・なぜ・誰のために
2. **機能分解** — 独立してリリース可能な Feature 単位に分割（番号付きリスト）
   - 各 Feature に `feat/<name>` のブランチ名案を添える
   - 依存関係・推奨実装順序を明記する
3. **全体アーキテクチャ概要** — Feature 間の関係性
4. **リスク・制約** — 共通の前提条件・注意点

設計を `$EPIC_PLAN` として保持し、フェーズ 1.5 に進む。

## フェーズ 1.5: BALTHASAR（Epic 設計レビュー）

`/balthasar` スキルのステップ 2〜3 に従い、**`$EPIC_PLAN` をレビュー対象として** BALTHASAR を実行する。

> diff ではなく Epic 設計テキストを渡す。BALTHASAR への指示：「以下の Epic 設計プランを設計・アーキテクチャ観点でレビューしてください」

結果を `$BALTHASAR_EPIC_REVIEW` として保持し、フェーズ 2 に進む。

## フェーズ 2: CHECK（ユーザー確認）✋

以下の形式で提示し、**必ずここで停止してユーザーの入力を待つ**：

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
- **はい / y / OK** → GitHub Issue 作成・フィーチャーループ開始
- **修正: 〜** → 分解案を修正して再提示（BALTHASAR 再実行）
- **いいえ / n** → 中断
```

承認後、`ExitPlanMode` してフェーズ 3 に進む。

## フェーズ 3: ISSUE 作成

各 Feature に対して GitHub Issue を作成する：

```bash
ISSUE_URL=$(gh issue create \
  --title "feat(<name>): <日本語タイトル>" \
  --body "$(cat <<'EOF'
## 概要
[Feature の説明]

## 実装内容
- ...

## 受け入れ条件
- [ ] ...
EOF
)")
ISSUE_NUM=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$')
```

> **注意:** `--title` に特殊文字（`"`、`$`、バッククォート等）が含まれる場合は適切にクォートすること。

`$ISSUE_NUM` を `$ISSUE_LIST` に追記する（例: `ISSUE_LIST+=("$ISSUE_NUM")`）。全 Feature 分繰り返した後、Issue 一覧をユーザーに提示する。

## フェーズ 4: FEATURE LOOP（1 件ずつ）

`$ISSUE_LIST` の先頭から順に、以下を繰り返す：

### 各 Feature の開始確認 ✋

```
Issue #N: feat/<name> — [タイトル]

この Feature の実装に着手しますか？
- **はい / y** → /dev-flow を開始
- **スキップ** → 次の Issue へ
- **終了** → ループを中断
```

### /dev-flow の実行

`/dev-flow` スキルを実行する。**ただし、フェーズ 1（PLAN）の要件として当該 Issue の内容を使用する。**

> dev-flow 内の BALTHASAR レビューはプランに対して実行される（通常どおり）。

### PR 作成後に停止

dev-flow の フェーズ 7（PR 作成）が完了したら停止し、次を提示する：

```
✓ Issue #N: PR 作成完了 → <PR URL>

次の Feature に進みますか？
- **はい / y** → Issue #M: feat/<next-name> を開始
- **あとで** → ここで終了（再開は /epic-flow #M で指定可）
```

### ループ終了

全 Issue を処理したら：

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
