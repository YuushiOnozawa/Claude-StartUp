---
name: pr-review-respond
description: PR review feedback response cycle skill. Use this skill EVERY TIME the user asks to respond to PR review comments, handle new review feedback, reflect reviewer指摘, or iterate on bot/human review on a pull request. Handles comment retrieval, code-reviewer second opinion, approach confirmation, implementation, commit, push, and per-comment replies. Trigger on: "レビュー対応", "PRレビュー対応", "レビュー反映", "レビューコメント対応", "Geminiの指摘", "pr-review-respond", "また指摘きてる", or any request to process new review comments on the current PR.
---

# Review-Respond Skill

PR に新しく付いたレビューコメント (Gemini / 人間) を取り込み、code-reviewer に第 2 意見を求め、ユーザー承認の上で実装・コミット・push・返信までを 1 サイクルで完結させる。

## 事前条件

- `gh` CLI が認証済み
- 作業中ブランチがリモートに push 済み
- 対象 PR が open 状態
- ユーザーの作業コンテキストで「レビューが来た」文脈であること

## ステップ 1: PR 特定

現在のブランチから PR を特定する。

```bash
git branch --show-current
gh pr view --json number,headRefName,baseRefName,url
```

`gh pr view` が失敗する場合は、ユーザーに PR 番号または URL を尋ねる。`main` / `master` 直接作業時は中断する。

以降、PR 番号を `$PR_NUM`、リポジトリを `$OWNER/$REPO` として扱う (必要に応じて `gh repo view --json nameWithOwner` で取得)。

## ステップ 2: 新規レビューコメント取得

### PR レビューサマリ（全体コメント）の取得

```bash
gh api repos/$OWNER/$REPO/pulls/$PR_NUM/reviews \
  --jq '.[] | select(.user.login != "YuushiOnozawa") | {id, user: .user.login, state, submitted_at, body}'
```

### 行別コメント (inline review) の取得

自分の最新返信以降のコメントを対象に絞る:

```bash
gh api repos/$OWNER/$REPO/pulls/$PR_NUM/comments \
  --jq '.[] | {id, user: .user.login, path, line, in_reply_to_id, created_at, body}'
```

抽出ルール:
- 自分 (`gh api user --jq .login` で取得) の最終返信コメントの `created_at` より後のコメント
- かつ bot (`gemini-code-assist[bot]` 等) または他の reviewer のもの
- `in_reply_to_id` が既に返信済みのものは除外してよい

取得結果を Claude のコンテキストに保存し、ユーザーにも要約を提示する (指摘ラベル: 前回採番の続き / 例: 指摘 H, I, J...)。

未対応の指摘が 0 件なら「新規指摘なし」と報告して終了。

## ステップ 3: code-reviewer への委譲

取得した指摘全件を **code-reviewer サブエージェント** (`Agent(subagent_type=code-reviewer)`) に渡す。プロンプトには必ず以下を含める:

1. PR 番号と URL
2. 前回までの対応経緯 (直近 2〜3 コミット分のメッセージ) ← `git log --oneline -5` から抽出
3. 対象ファイルの関連部分の**現状コード全文**
4. 取得した各指摘の正当性判定依頼 (HIGH/MEDIUM/LOW)
5. 独立観点で追加の問題がないかの調査依頼
6. 安全性に関わる指摘 (破壊的変更等) は慎重評価の指示
7. 出力語数上限 (300 語程度、日本語)

## ステップ 4: 対応方針の確認

code-reviewer の判定を**そのままユーザーに投げない**。指摘ごとに以下の形式で要約し、`AskUserQuestion` で方針を確認する:

| 指摘 | 行 | 内容 | code-reviewer 判定 |
|------|-----|------|-------------------|

`AskUserQuestion` のルール:
- 1 指摘 = 1 質問
- 最大 4 指摘まで 1 ターンで質問 (ツール制限)。5 件以上あれば HIGH/MEDIUM 優先で 4 件に絞るか、2 ターンに分割
- 各選択肢は「採用 (推奨)」「却下 (推奨)」「代替案」などで 2〜4 個
- code-reviewer が明確な推奨を出している場合は「(推奨)」マークを先頭選択肢に付ける

## ステップ 5: 3 ファイル以上影響する場合はプランモード

ユーザー確定方針で `setup.sh` 等の単一ファイルで済むなら直接実装へ。3 ファイル以上に影響する場合はプランモードに入る (グローバル原則)。

## ステップ 6: 実装

- `Edit` / `Write` で修正
- 構文チェック可能な言語なら必ず実行 (例: `bash -n`)
- 破壊的変更を含む場合は一時ディレクトリ等で単体動作確認
- 既存コードスタイルに合わせる

## ステップ 7: コミット

`/commit` スキルのルールに従う (このファイルを参照):
- Conventional Commits 形式 (type(scope): 日本語 subject)
- HEREDOC 形式
- `Co-Authored-By: Claude <noreply@anthropic.com>`
- main / master 直接コミット禁止
- `--no-verify` 禁止

1 コミット = 1 関心事の原則を守る。レビュー複数対応でも「単一 PR の指摘反映」として 1 コミットにまとめてよい場合が多いが、独立した関心事 (例: バグ修正 + リファクタ) なら分割する。

## ステップ 8: push

```bash
git push
```

force push は禁止。失敗する場合は `git pull --rebase` を検討する前にユーザーに確認する。

## ステップ 9: 返信 POST

**採否に関わらず全指摘に返信する**。GitHub の review スレッドに対する返信は以下:

```bash
gh api -X POST repos/$OWNER/$REPO/pulls/$PR_NUM/comments/$COMMENT_ID/replies \
  -f body="@$REVIEWER_HANDLE

<日本語の返信本文>" \
  --jq '.html_url'
```

返信本文の原則:
- 採用の場合: 何をどう対応したか + コミットハッシュ
- 却下の場合: 理由を明記 (技術的根拠 / 過去指摘への言及 / ユーザー意向)
- 代替案採用の場合: 元提案との違いと理由
- ボット宛は `@gemini-code-assist` など正しいハンドルを使う
- 日本語 (人間 reviewer が英語ネイティブなら英語可)

同一コメントに複数指摘が含まれる場合は 1 返信にまとめる。

## ステップ 10: 報告

ユーザーに以下を報告する:
- 変更内容の要約 (1〜2 行)
- コミットハッシュ
- 各返信の URL (discussion_r... のアンカー付き)
- 次のレビューサイクル待ち状態であること

## 禁止事項

- ユーザー承認なしの実装開始
- code-reviewer をスキップした実装
- レビュー指摘の無視 (採用しない場合も必ず返信で理由を述べる)
- 自己返信 (自分の前回返信に対する返信は無意味)
- `main` / `master` への直接コミット
- force push

## サイクル繰り返し

このスキルは 1 サイクル分。返信後に新しい指摘が来たら再度このスキルを呼ぶ。
