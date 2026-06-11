---
name: pr-review
description: PR レビュースキル。magi-hard（MAGI 5体）でレビューを実行し GitHub にコメント投稿する。HIGH/MEDIUM 指摘があれば /pr-review-respond と交互に回して LGTM まで到達させる。Trigger: "PRレビュー", "pr-review", "レビューして", "コードレビュー", "review PR", "MAGIにレビューさせて", "PRをレビューして"
---

# PR Review Skill

PR に対して `/magi-hard` を実行し、MAGI 5体によるレビュー結果を GitHub に投稿する。
HIGH/MEDIUM 指摘がある場合は `/pr-review-respond` で対応し、このスキルを再実行する——LGTM まで繰り返す。

## 事前条件

- `gh` CLI が認証済み
- 作業中ブランチがリモートに push 済み
- 対象 PR が open 状態

## ステップ 1: PR 特定

現在のブランチから PR を特定する。

```bash
git branch --show-current
gh pr view --json number,headRefName,baseRefName,url,state
```

- closed / merged PR の場合は「PR はすでに closed です」と報告して終了
- draft の場合はユーザーに確認する
- `main` / `master` 直接作業時は中断する

以降、PR 番号を `$PR_NUM`、リポジトリを `$OWNER/$REPO` として扱う（`gh repo view --json nameWithOwner` で取得）。

## ステップ 2: magi-hard の実行

`/magi-hard` スキルを実行する。

magi-hard は以下を担う：
- MELCHIOR→BALTHASAR→CASPER→METATRON→SANDALPHON の順次実行
- 行番号＋種別フラグの共有による重複排除
- PR にサマリコメント投稿（先行）→ HIGH/MEDIUM 指摘をインラインコメントとして投稿

## ステップ 3: 次のアクション判定

magi-hard の完了後、以下の基準でユーザーに報告する：

```
## PR レビュー完了

| ペルソナ | HIGH | MEDIUM | LOW |
|---------|------|--------|-----|
| MELCHIOR（コード品質・バグ） | N | M | K |
| BALTHASAR（設計・アーキテクチャ） | N | M | K |
| CASPER（ルール遵守） | N | M | K |
| METATRON（セキュリティ） | N | M | K |
| SANDALPHON（実行環境・デプロイ） | N | M | K |
```

### 次のアクション

- **HIGH/MEDIUM 指摘あり** → `/pr-review-respond` で対応 → 対応完了後に再度 `/pr-review` を実行
- **HIGH/MEDIUM 指摘なし** → LGTM（マージ準備完了）

## 注意事項

- レビュー結果の修正対応は `/pr-review-respond` スキルで行う
- `pr-review ↔ pr-review-respond` のループで LGTM まで到達させる
