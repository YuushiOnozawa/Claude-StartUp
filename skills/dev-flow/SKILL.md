---
name: dev-flow
desc: 単一機能の設計→実装→MAGIレビュー→PR作成までのフルサイクル開発ワークフロー。Trigger: "/dev-flow", "dev-flow"。自然言語トリガーは /epic-flow が担う。
---

# DEV-FLOW スキル

「作りたいもの」から PR 作成までを一気通貫で進める開発ワークフロー。

| # | フェーズ | 内容 | 停止点 |
|---|---------|------|--------|
| 1 | PLAN | 設計プラン作成 | |
| 1.5 | BALTHASAR | 設計観点レビュー | |
| 2 | CHECK | ユーザー承認 | ✋ 停止 |
| 3 | BRANCH | ブランチ作成 | |
| 4 | IMPL | 実装 | |
| 5 | REVIEW | magi-fast → 修正ループ | |
| 6 | COMMIT | コミット | |
| 7 | PR | PR 作成 | |

---

## フェーズ 1: PLAN（設計）

`EnterPlanMode` を呼び出し、以下を含む設計プランを作成する：

1. **要件整理** — 何を・なぜ・誰のために
2. **実装方針** — アーキテクチャ・使用技術・主要な設計決定
3. **影響ファイル** — 新規作成・変更・削除するファイル一覧
4. **実装ステップ** — 番号付きの具体的な手順
5. **リスク・制約** — 注意点・前提条件

設計プランを `$PLAN` として保持し、フェーズ 1.5 に進む。

## フェーズ 1.5: BALTHASAR（設計レビュー）

`/balthasar` スキルのステップ 2〜3 に従い、**`$PLAN` をレビュー対象として** BALTHASAR を実行する。

> diff ではなくプランテキストを渡す。BALTHASAR への指示：「以下の設計プランを設計・アーキテクチャ観点でレビューしてください」

結果を `$BALTHASAR_PLAN_REVIEW` として保持し、フェーズ 2 に進む。

## フェーズ 2: CHECK（ユーザー確認）✋

以下の形式でプランと BALTHASAR レビューを提示し、**必ずここで停止してユーザーの入力を待つ**：

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
- **はい / y / OK** → ブランチ作成・実装開始
- **修正: 〜** → プランを修正して再提示（BALTHASAR 再実行）
- **いいえ / n** → 中断
```

**修正** が来た場合はフェーズ 1 に戻り、修正を反映したプランを再作成して BALTHASAR も再実行する。
承認後、`ExitPlanMode` してフェーズ 3 に進む。

## フェーズ 3: BRANCH（ブランチ作成）

現在のブランチを確認する：

```bash
git branch --show-current
```

すでに `main` / `master` 以外のブランチにいる場合はスキップ。

`main` / `master` にいる場合：

### `new-worktree` が利用可能な場合（Issue #53）

```bash
command -v new-worktree > /dev/null 2>&1
```

利用可能であれば、ユーザーに確認する：

```
worktree を作成しますか（並列開発用の独立した作業ディレクトリ）？
- **worktree / w** → new-worktree feat/<機能名> で作成
- **branch / b** → 通常のブランチ切り替え（git checkout -b feat/<機能名>）
```

### `new-worktree` が使えない場合

通常のブランチを作成する：

```bash
git checkout -b feat/<機能名>   # 機能追加
git checkout -b fix/<バグ名>    # バグ修正
```

ブランチ名は要件から自動生成する（英語・ケバブケース）。

## フェーズ 4: IMPL（実装）

承認済みプランの実装ステップを順に実行する。

完了後：
- `git status` で変更ファイルを確認
- `git diff` で差分をサマリー表示

フェーズ 5 に進む。

## フェーズ 5: REVIEW → FIX ループ

`/magi-fast` スキルを実行する。

### HIGH が 0 件 → フェーズ 6 へ

### HIGH が 1 件以上 → 修正

各 HIGH 指摘に対して修正案を提示し、ユーザーが採否を判断して修正する。
修正後に `/magi-fast` を再実行する。HIGH がゼロになるまでこのループを繰り返す。

## フェーズ 6: COMMIT

`/commit` スキルを実行する。

## フェーズ 7: PR 作成

1. リモートにプッシュ：

```bash
git push -u origin <branch>
```

2. PR を作成（タイトル・本文は変更内容から生成）：

```bash
PR_URL=$(gh pr create --title "<type>(<scope>): <日本語タイトル>" --body "$(cat <<'EOF'
## 概要
[変更内容の 1〜3 行サマリー]

## 変更点
- ...

## テスト
- [ ] ...

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)")
```

3. `$PR_URL` をユーザーに提示する。

---

## PR 後の推奨フロー（参考）

```
/pr-review-respond  → 人間レビュー指摘への対応
/magi-hard          → MAGI 5体による PR レビュー
/magi-fast          → 修正後の品質確認（必要に応じて）
マージ
```
