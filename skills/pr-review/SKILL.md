---
name: pr-review
description: PR レビュースキル。magi-hard（MAGI 6体）でレビューを実行する。summary JSON を基準に判定し、GitHub 投稿は F7 poster に委譲する。HIGH/MEDIUM 指摘があれば /pr-review-respond と交互に回して LGTM まで到達させる。Trigger: "PRレビュー", "pr-review", "レビューして", "コードレビュー", "review PR", "MAGIにレビューさせて", "PRをレビューして"
---

# PR Review Skill

PR に対して `/magi-hard` を実行し、MAGI 6体（MELCHIOR→BALTHASAR→CASPER→METATRON→SANDALPHON→LELIEL）のレビュー結果を summary JSON 基準で判定する。指摘は magi-hard の poster が GitHub に冪等投稿する（正本は run dir の `review-plan.json`）。

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

`/magi-hard` スキルを実行する。完了後に出力された `$RUN_DIR/review-plan.json` と canonical summary を正本として扱う。

magi-hard は以下を担う：
- MELCHIOR→BALTHASAR→CASPER→METATRON→SANDALPHON→LELIEL の順次 sink 実行
- pre-triage、2段階 aggregate、Codex annotation
- `review-plan.json` と summary JSON の生成、poster による GitHub への冪等投稿

## ステップ 3: 次のアクション判定

Claude の目視カウント、raw persona artifact の全文再表示、全文の再集計は禁止する。magi-hard 完了後、`$RUN_DIR/review-plan.json` の summary と canonical summary だけを読む。

- persona の `parse_status != ok` が1件でもあれば「レビュー不完全 — LGTM 禁止、/magi-hard を再実行」と表示する。
- `needs_human > 0` なら「要人判断 N 件 — 解決まで LGTM 対象外」と表示する。
- raw HIGH または raw MEDIUM が1件でもあれば `/pr-review-respond` へ進む。指摘詳細は `$RUN_DIR/review-plan.json` と magi-hard の terminal 表示を参照する。
- 上記いずれもなく、UNKNOWN を含め raw counts が全てゼロなら LGTM と表示する。

```
## PR レビュー完了

判定: レビュー不完全 / 要人判断 / 指摘対応 / LGTM
参照: $RUN_DIR/review-plan.json
```

## 注意事項

- レビュー結果の修正対応は `/pr-review-respond` スキルで行う
- GitHub へのサマリ・インラインコメント投稿は magi-hard の poster の責務である
- `false_positive` 除外や annotation unavailable は raw 基準の gate を緩和しない
- `pr-review ↔ pr-review-respond` のループで LGTM まで到達させる
