---
name: magi-hard
description: MAGI 5体（melchior→balthasar→casper→metatron→sandalphon）でPRレビューを行う。指摘をGitHubにコメント投稿する。Trigger: "/magi-hard", "magi-hard", "ハードレビュー", "PRをMAGIにレビューさせて"
---

# MAGI-HARD スキル

MAGI の5体を順次実行し、PR の全差分を深くレビューする。
各体は担当ドメインに専念し、ドメイン分離によって重複を防ぐ。
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
# .md ファイルをローカルLLMに渡す前に除外する（ロールプレイ指示の混入防止）
DIFF=$(printf '%s\n' "$DIFF" | awk '/^diff --git/{skip=($0 ~ /\.md /)} !skip')
```

差分が空の場合は「差分がありません」と報告して終了。

## ステップ 2: MELCHIOR 実行

`/melchior` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
結果を `$MELCHIOR_RESULT` として保持する。

## ステップ 3: BALTHASAR 実行

`/balthasar` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
結果を `$BALTHASAR_RESULT` として保持する。

## ステップ 4: CASPER 実行

`/casper` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
結果を `$CASPER_RESULT` として保持する。

## ステップ 5: METATRON 実行

`/metatron` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
結果を `$METATRON_RESULT` として保持する。

## ステップ 6: SANDALPHON 実行

`/sandalphon` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
結果を `$SANDALPHON_RESULT` として保持する。

## ステップ 7: サマリコメント投稿

5体のレビュー完了後、まず PR 全体に**サマリコメント**を1件投稿する。インライン指摘より先に投稿することで、レビュー全体像をレビュアーが把握しやすくなる。

```bash
SUMMARY_URL=$(gh api -X POST repos/$OWNER/$REPO/issues/$PR_NUM/comments \
  -f body="## MAGI-HARD レビュー完了

| ペルソナ | HIGH | MEDIUM | LOW |
|---------|------|--------|-----|
| MELCHIOR（コード品質・バグ） | N | M | K |
| BALTHASAR（設計・アーキテクチャ） | N | M | K |
| CASPER（ルール遵守） | N | M | K |
| METATRON（セキュリティ） | N | M | K |
| SANDALPHON（実行環境・デプロイ） | N | M | K |

**HIGH: N件 / MEDIUM: M件 / LOW: K件**（LOW はインラインコメント対象外）

> 各行への指摘はインラインコメントとして続けて投稿します。対応完了後は各インラインコメントに返信してください（\`/pr-review-respond\` で自動化可能）" \
  --jq '.html_url')
```

## ステップ 8: GitHub インラインコメント投稿

5体の結果から HIGH/MEDIUM 指摘を抽出し、**指摘ごとに個別の PR インラインコメント**として投稿する。

### インラインコメントの投稿方法

各 HIGH/MEDIUM 指摘について、出力形式 `### [HIGH/MEDIUM] ファイルパス:行番号 — 見出し` から `path` と `line` を抽出し、以下のコマンドで投稿する：

```bash
gh api -X POST repos/$OWNER/$REPO/pulls/$PR_NUM/comments \
  -f body="[MAGI-HARD] **[HIGH] MELCHIOR（コード品質・バグ）**

<指摘内容>" \
  -f path="scripts/example.sh" \
  -F line=17 \
  -f side="RIGHT" \
  -f commit_id="$HEAD_SHA" \
  --jq '.html_url'
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

インラインコメント: N件投稿
サマリコメント: $SUMMARY_URL

次のアクション:
- 指摘への対応・返信: `/pr-review-respond` を実行
- 指摘なし・軽微な場合: マージ準備完了
```
