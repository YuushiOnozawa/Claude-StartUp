---
name: pr-review
description: PR レビュースキル。Gemini Code Assist（自動実行済み）のレビューコメントを取得・表示し、続けて /code-review プラグインを実行する。両方の結果を統合してサマリを提示する。Trigger: "PRレビュー", "pr-review", "レビューして", "コードレビュー", "Geminiのレビュー確認", "review PR"
---

# PR Review Skill

PR に対して Gemini Code Assist のレビュー結果を取得し、/code-review プラグインを実行して、両方の指摘をまとめて提示する。

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

## ステップ 2: Gemini レビューコメントの取得

Gemini Code Assist のレビューコメントを取得して表示する。

### PR レビュー（ファイル全体レビュー）の取得

```bash
gh api repos/$OWNER/$REPO/pulls/$PR_NUM/reviews \
  --jq '[.[] | select(.user.login | test("gemini"; "i"))] | {count: length, reviews: map({id, state, submitted_at, body})}'
```

### インラインコメントの取得

```bash
gh api repos/$OWNER/$REPO/pulls/$PR_NUM/comments \
  --jq '[.[] | select(.user.login | test("gemini"; "i"))] | {count: length, comments: map({id, path, line, body})}'
```

結果を以下の形式でユーザーに提示する：

```
## Gemini Code Assist レビュー結果

レビューコメント: N 件
インラインコメント: M 件

### レビュー本文
<本文があれば表示>

### インライン指摘一覧
| # | ファイル | 行 | 内容 |
|---|----------|-----|------|
| 1 | path/to/file.ts | 42 | <指摘内容の要約> |
...
```

Gemini のコメントが 0 件の場合は「Gemini のレビューコメントはまだありません」と表示して続行する。

## ステップ 3: /code-review プラグインの実行

/code-review コマンドを実行する。

このコマンドは以下のフローで PR を解析し GitHub にコメントを投稿する：
- 5 本の並列 Sonnet エージェントで独立レビュー（CLAUDE.md 準拠・バグ・履歴分析など）
- Haiku で各指摘を 0–100 スコアリング
- スコア 80 以上のみ GitHub にコメント投稿

## ステップ 4: サマリ提示

両方のレビューが完了したら、以下のサマリをユーザーに提示する：

```
## PR レビュー完了

| レビュアー | 指摘数 | 状態 |
|-----------|--------|------|
| Gemini Code Assist | N 件 | 確認済み |
| /code-review (Claude) | M 件 | GitHub にコメント済み |

### 次のアクション
- 指摘への対応: `/pr-review-respond` を実行
- 指摘なし・軽微な場合: マージ準備完了
```

## 注意事項

- Gemini は PR 作成時に自動実行済みのため、このスキルは「確認と /code-review の追加実行」が目的
- レビュー結果の修正対応は `/pr-review-respond` スキルで行う
- `/code-review` は 1 PR につき 1 回が基本（既にレビュー済みの場合はスキップされる）
