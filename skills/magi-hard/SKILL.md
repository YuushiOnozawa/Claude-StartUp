---
name: magi-hard
description: MAGI 5体（melchior→balthasar→casper→metatron→sandalphon）でPRレビューを行う。指摘をGitHubにコメント投稿する。Trigger: "/magi-hard", "magi-hard", "ハードレビュー", "PRをMAGIにレビューさせて"
---

# MAGI-HARD スキル

MAGI の5体を順次実行し、PR の全差分を深くレビューする。
前の体の指摘（行番号＋種別フラグ）を後続体に渡すことで重複を避け、未指摘の観点に集中させる。
HIGH/MEDIUM 指摘を GitHub PR コメントとして投稿する。

## 前提

- `gh` CLI が認証済み
- 作業中ブランチがリモートに push 済み
- 対象 PR が open 状態

## ステップ 1: PR 特定と差分取得

```bash
git branch --show-current
gh pr view --json number,headRefName,baseRefName,url,state
```

- closed / merged の場合は「PR はすでに closed です」と報告して終了
- PR 番号を `$PR_NUM`、リポジトリを `$OWNER/$REPO` として保持

PR の全差分を取得：

```bash
DIFF=$(gh pr diff $PR_NUM 2>/dev/null)
```

差分が空の場合は「差分がありません」と報告して終了。

## ステップ 2: フラグ管理

`$FLAGS` 変数で既指摘フラグを管理する（初期値: 空）。

各体の実行後、HIGH/MEDIUM 指摘の行番号と種別を以下の形式で `$FLAGS` に追記する：
```
L<行番号>:<種別>
```
例: `L42:BUG, L87:DESIGN, L103:RULE`

種別コード:
| 観点 | コード |
|------|--------|
| コード品質・バグ | BUG |
| 設計・アーキテクチャ | DESIGN |
| ルール遵守 | RULE |
| セキュリティ | SECURITY |
| 実行環境・デプロイ | DEPLOY |

## ステップ 3: MELCHIOR 実行

`/melchior` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
（`$FLAGS` は空のため、フラグ付加なし）

結果を `$MELCHIOR_RESULT` として保持し、HIGH/MEDIUM 指摘から `$FLAGS` を更新する。

## ステップ 4: BALTHASAR 実行

`/balthasar` スキルの手順に従い、`$DIFF` を渡す。

以下のフラグ情報をプロンプトの先頭に付加する：
```
既に指摘済み（重複は避けてください）: $FLAGS
```

結果を `$BALTHASAR_RESULT` として保持し、`$FLAGS` を更新する。

## ステップ 5: CASPER 実行

`/casper` スキルの手順に従い、同様に `$FLAGS` を付加して実行する。
結果を `$CASPER_RESULT` として保持し、`$FLAGS` を更新する。

## ステップ 6: METATRON 実行

`/metatron` スキルの手順に従い、同様に `$FLAGS` を付加して実行する。
結果を `$METATRON_RESULT` として保持し、`$FLAGS` を更新する。

## ステップ 7: SANDALPHON 実行

`/sandalphon` スキルの手順に従い、同様に `$FLAGS` を付加して実行する。
結果を `$SANDALPHON_RESULT` として保持する。

## ステップ 8: GitHub PR コメント投稿

5体の結果から HIGH/MEDIUM 指摘を抽出し、PR にコメントとして投稿する。

以下の形式で1件のコメントにまとめて投稿する：

```bash
gh api -X POST repos/$OWNER/$REPO/issues/$PR_NUM/comments \
  -f body="## MAGI-HARD レビュー

<5体の指摘サマリ>"
```

コメント本文の形式：
```
## MAGI-HARD レビュー

### MELCHIOR（コード品質・バグ）
<HIGH/MEDIUM 指摘のみ抜粋>

### BALTHASAR（設計・アーキテクチャ）
<HIGH/MEDIUM 指摘のみ抜粋>

### CASPER（ルール遵守）
<HIGH/MEDIUM 指摘のみ抜粋>

### METATRON（セキュリティ）
<HIGH/MEDIUM 指摘のみ抜粋>

### SANDALPHON（実行環境・デプロイ）
<HIGH/MEDIUM 指摘のみ抜粋>

---
HIGH: N件 / MEDIUM: M件 / LOW: K件（LOW は GitHub 投稿対象外）
```

指摘が0件の体は「指摘事項なし」と1行だけ記載する。

## ステップ 9: 結果のサマリ表示

ユーザーに以下を表示する：

```
## MAGI-HARD 完了

| ペルソナ | HIGH | MEDIUM | LOW |
|---------|------|--------|-----|
| MELCHIOR | N | M | K |
| BALTHASAR | N | M | K |
| CASPER | N | M | K |
| METATRON | N | M | K |
| SANDALPHON | N | M | K |

GitHub コメント: <URL>

次のアクション:
- 指摘への対応: `/pr-review-respond` を実行
- 指摘なし・軽微な場合: マージ準備完了
```
