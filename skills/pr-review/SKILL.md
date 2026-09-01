---
name: pr-review
description: PR レビュースキル。`/review-hard` を実行し、選択した backend（magi|codex）でレビュー結果を GitHub に投稿する。ブロック指摘（blocking_count≥1）または要人手確認があれば /pr-review-respond と交互に回して LGTM まで到達させる。Trigger: "PRレビュー", "pr-review", "レビューして", "コードレビュー", "review PR", "MAGIにレビューさせて", "PRをレビューして"
---

# PR Review Skill

PR に対して `/review-hard` を実行し、選択した backend（magi|codex）でレビュー結果を GitHub に投稿する。
ブロック指摘（`blocking_count≥1`）または要人手確認がある場合は `/pr-review-respond` で対応し、このスキルを再実行する——LGTM まで繰り返す。

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

## ステップ 2: review-hard の実行

backend は次の優先順位で決める（**`REVIEW_HARD_BACKEND_OVERRIDE` → `REVIEW_HARD_BACKEND` → AskUserQuestion（初回のみ）**）:

1. `$REVIEW_HARD_BACKEND_OVERRIDE` が `magi` または `codex` なら、それを effective backend にする。
2. override が未設定・不正で、`$REVIEW_HARD_BACKEND` が `magi` または `codex` なら、それを使う。
3. どちらも有効値を持たないときだけ、初回の `/review-hard` が backend 選択 UI（AskUserQuestion）を 1 回出す。

`/pr-review` がレビュー開始時に確定した effective backend を、`/pr-review` ⇄ `/pr-review-respond` ループ全体で保持し、ループ途中で状態変数を再評価しない。ループを離脱するとき（LGTM 到達または中断）に `$REVIEW_HARD_BACKEND_OVERRIDE` を破棄する。`$REVIEW_HARD_BACKEND` / `$REVIEW_HARD_BACKEND_OVERRIDE` は当該 PR のレビューにだけ有効で、別 PR に持ち越さない。

`/review-hard` は選択した backend の hard レビューを実行し、結果を GitHub に投稿して `$REVIEW_DISPATCH_RESULT`（envelope JSON のパス）を返す。

## ステップ 3: 次のアクション判定

`/review-hard` 完了後、`$REVIEW_DISPATCH_RESULT` の envelope から backend 名、`gate_decision`、`blocking_count`、`manual_review`（および `manual_review_required`）をユーザーに報告する。persona 別の内訳が必要な場合は `native_result` から表示する。

```
## PR レビュー完了

backend: `<magi|codex>`
gate_decision: `<lgtm|block|manual|indeterminate>`
blocking_count: `<非負整数|null>`
manual_review: `<内容|null>`
```

### 次のアクション

envelope を次の順で評価し、**先に一致したもの**を採る。

1. **`post_state == "post_failed"`** → fail-closed。GitHub へ1件も投稿されていないことが保証されている
   状態（dispatch の `/review-post` 未実行、または `/review-post` が API 呼び出し前の契約違反で終了）。
   `/pr-review-respond` ループへは入らず、`failure_reason` を提示して `/review-hard` 再実行を促して
   停止する。
2. **`dispatch_status != "complete"` または `blocking_count == null` または `gate_decision == "indeterminate"`**
   → fail-closed。respond ループへ入らず LGTM も出さない。分岐は共通キー（`post_state` /
   `dispatch_status`）だけで行い、`native_result` は読まない。
   - `post_state == "posted"`（レビュー結果は GitHub へ投稿済み、または投稿状況が不明で保守的に
     投稿済み扱い）→ `/review-hard` の盲目的再実行は促さない。「GitHub の既存コメントを確認し、
     重複投稿を避けるため手動で対応するか、既存コメントを削除してから再実行するか判断してほしい」と
     `failure_reason` を添えて提示し停止する。
   - それ以外 → `failure_reason` を提示し、手動レビューまたは `/review-hard` 再実行を促して停止する。
3. **`blocking_count ≥ 1` または `manual_review_required == true`** → `/pr-review-respond` で対応 →
   対応完了後に再度 `/pr-review` を実行。
4. **`lgtm_eligible == true`** → LGTM（マージ準備完了）。`blocking_count == 0` かつ
   `manual_review_required == false` の見かけだけでは LGTM にしない。
5. **上記いずれにも当てはまらない**（`lgtm_eligible != true` だが respond 対象でもない）→ fail-closed。

投稿対象は `final_gate == "block"` の全件であり、`importance: null` を除外しない（PR #407 の確定事項と同じ）。

## 注意事項

- レビュー結果の修正対応は `/pr-review-respond` スキルで行う
- `pr-review ↔ pr-review-respond` のループで LGTM まで到達させる
