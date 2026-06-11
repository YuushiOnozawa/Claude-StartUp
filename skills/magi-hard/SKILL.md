---
name: magi-hard
description: MAGI 5体（melchior→balthasar→casper→metatron→sandalphon）でPRレビューを行う。指摘をGitHubにコメント投稿する。Trigger: "/magi-hard", "magi-hard", "ハードレビュー", "PRをMAGIにレビューさせて"
---

# MAGI-HARD スキル

MAGI の5体を順次実行し、PR の全差分を深くレビューする。
前の体の指摘（行番号＋種別フラグ）を後続体に渡すことで重複を避け、未指摘の観点に集中させる。
HIGH/MEDIUM 指摘を GitHub PR のインラインコメントとして投稿し、サマリも別途投稿する。

## 前提

- `gh` CLI が認証済み
- 作業中ブランチがリモートに push 済み
- 対象 PR が open 状態

## ステップ 1: PR 特定と差分取得

```bash
git branch --show-current
gh pr view --json number,headRefName,baseRefName,url,state
HEAD_SHA=$(gh api repos/$OWNER/$REPO/pulls/$PR_NUM --jq .head.sha)
```

- closed / merged の場合は「PR はすでに closed です」と報告して終了
- PR 番号を `$PR_NUM`、リポジトリを `$OWNER/$REPO`、HEAD コミットを `$HEAD_SHA` として保持

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

## ステップ 3〜7: 各体の実行（**必ず逐次。並列化禁止**）

> ⚠️ ステップ 3〜7 は **MELCHIOR → BALTHASAR → CASPER → METATRON → SANDALPHON の順に1体ずつ実行すること**。
> 前の体の結果から `$FLAGS` を更新して次の体に渡すため、並列実行すると FLAGS が空のまま渡され重複排除が機能しない。

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

## ステップ 8: GitHub インラインコメント投稿

5体の結果から HIGH/MEDIUM 指摘を抽出し、**指摘ごとに個別の PR インラインコメント**として投稿する。

### インラインコメントの投稿方法

各 HIGH/MEDIUM 指摘について、出力形式 `### [HIGH/MEDIUM] ファイルパス:行番号 — 見出し` から `path` と `line` を抽出し、以下のコマンドで投稿する：

```bash
COMMENT_URL=$(gh api -X POST repos/$OWNER/$REPO/pulls/$PR_NUM/comments \
  -f body="[MAGI-HARD] **[HIGH] MELCHIOR（コード品質・バグ）**

<指摘内容>" \
  -f path="scripts/example.sh" \
  -F line=17 \
  -f side="RIGHT" \
  -f commit_id="$HEAD_SHA" \
  --jq '.html_url')
```

コメント本文の形式：
```
[MAGI-HARD] **[HIGH/MEDIUM] <ペルソナ名>（<観点>）**

<指摘の詳細内容>
```

### ラインが差分にない場合のフォールバック

指定した `line` が PR diff に含まれていない場合（API エラー `422`）は、インラインコメントの代わりに通常の PR コメントとして投稿する：

```bash
gh api -X POST repos/$OWNER/$REPO/issues/$PR_NUM/comments \
  -f body="[MAGI-HARD] **[HIGH/MEDIUM] <ペルソナ>** `ファイルパス:行番号`

<指摘内容>"
```

### 投稿結果の保持

投稿した全コメントの URL を `$INLINE_COMMENT_URLS` リストとして保持する（ステップ 9 のサマリで使用）。

## ステップ 9: サマリコメント投稿

全指摘のインラインコメント投稿後、PR 全体に**サマリコメント**を1件投稿する：

```bash
gh api -X POST repos/$OWNER/$REPO/issues/$PR_NUM/comments \
  -f body="## MAGI-HARD レビュー完了

| ペルソナ | HIGH | MEDIUM | LOW |
|---------|------|--------|-----|
| MELCHIOR（コード品質・バグ） | N | M | K |
| BALTHASAR（設計・アーキテクチャ） | N | M | K |
| CASPER（ルール遵守） | N | M | K |
| METATRON（セキュリティ） | N | M | K |
| SANDALPHON（実行環境・デプロイ） | N | M | K |

**HIGH: N件 / MEDIUM: M件 / LOW: K件**（LOW はインラインコメント対象外）

### インラインコメント一覧
<各指摘のURL を箇条書きで列挙>

> 対応完了後は各インラインコメントに返信してください（\`/pr-review-respond\` で自動化可能）"
```

## ステップ 10: 結果のサマリ表示

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

インラインコメント: N件投稿
サマリコメント: <URL>

次のアクション:
- 指摘への対応・返信: `/pr-review-respond` を実行
- 指摘なし・軽微な場合: マージ準備完了
```
