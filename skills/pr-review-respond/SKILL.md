---
name: pr-review-respond
description: PR review feedback response cycle skill. Use this skill EVERY TIME the user asks to respond to PR review comments — whether from human reviewers or MAGI-HARD inline comments. Handles comment retrieval, Codex audit second opinion, approach confirmation, implementation, commit, push, and per-comment replies. Trigger on: "レビュー対応", "PRレビュー対応", "レビュー反映", "レビューコメント対応", "MAGIの指摘", "pr-review-respond", "また指摘きてる", or any request to process new review comments on the current PR.
---

# Review-Respond Skill

PR に付いたレビューコメント（人間レビュアー・MAGI-HARD 両方）を取り込み、Codex 監査で第 2 意見を求め、ユーザー承認の上で実装・コミット・push・返信までを 1 サイクルで完結させる。

## 事前条件

- `gh` CLI が認証済み
- 作業中ブランチがリモートに push 済み
- 対象 PR が open 状態
- MAGI-HARD または人間レビュアーによる未対応コメントがある状態であること

## ステップ 1: PR 特定

現在のブランチから PR を特定する。

```bash
git branch --show-current
gh pr view --json number,headRefName,baseRefName,url
```

`gh pr view` が失敗する場合は、ユーザーに PR 番号または URL を尋ねる。`main` / `master` 直接作業時は中断する。

以降、PR 番号を `$PR_NUM`、リポジトリを `$OWNER/$REPO` として扱う (必要に応じて `gh repo view --json nameWithOwner` で取得)。

## ステップ 2: 新規レビューコメント取得

自分のログインを先に取得する：

```bash
MY_LOGIN=$(gh api user --jq .login)
```

### (A) 人間レビュアーのコメント取得

PR レビューサマリ（全体コメント）:

```bash
gh api repos/$OWNER/$REPO/pulls/$PR_NUM/reviews \
  --jq '.[] | select(.user.login != "'$MY_LOGIN'") | {id, user: .user.login, state, submitted_at, body}'
```

行別コメント（自分の最終返信以降のもの）:

```bash
gh api repos/$OWNER/$REPO/pulls/$PR_NUM/comments \
  --jq '.[] | {id, user: .user.login, path, line, in_reply_to_id, created_at, body}'
```

抽出ルール:
- 自分 (`$MY_LOGIN`) の最終返信コメントの `created_at` より後のコメント
- かつ人間レビュアーのコメント（自分以外、かつ MAGI コメントでない）
- `in_reply_to_id` が既に返信済みのものは除外してよい

### (B) MAGI インラインコメントの取得

magi-hard が投稿したインラインコメント（未対応のもの）を取得する：

```bash
gh api repos/$OWNER/$REPO/pulls/$PR_NUM/comments \
  --jq '[.[] | select(.body | startswith("[MAGI-HARD]")) | select(.in_reply_to_id == null)] | .[] | {id, path, line, created_at, body}'
```

さらに、それぞれのコメントに「自分の返信が既にあるか」を確認し、返信済みのものは除外する：

```bash
# 返信済みコメント ID の一覧（in_reply_to_id が MAGI コメント ID と一致するもの）
gh api repos/$OWNER/$REPO/pulls/$PR_NUM/comments \
  --jq '[.[] | select(.user.login == "'$MY_LOGIN'") | .in_reply_to_id] | map(tostring)'
```

未返信の MAGI 指摘を `$MAGI_FINDINGS` として保持する。

### 取得結果の整理

両方のコメントを統合し、ユーザーに要約を提示する：
- 人間レビュアー指摘: アルファベットラベル（前回採番の続き、例: 指摘 H, I, J...）
- MAGI 指摘: M-1, M-2... のラベルで区別する

未対応の指摘が合計 0 件なら「新規指摘なし」と報告して終了。

## ステップ 3: Codex 監査

取得した指摘全件を **Codex 監査**（`skills/magi-common/references/codex-audit.md`）で検証する。

### 3-1. Finding ID の付与

取得した全指摘（人間レビュアー・MAGI-HARD 両方）に `M-001`, `M-002`, ... の形式で連番を付与する。

```text
M-001: [HIGH] MAGI — filepath:line — headline
M-002: [human] @reviewer — filepath:line — summary
...
```

各エントリには指摘が MAGI 由来か人間レビュアー由来かを明記する。このリストを `$FINDING_LIST` として保持する（plain text）。

### 3-2. 追加コンテキストの収集

```bash
COMMIT_LOG=$(git log --oneline -5)
```

対象ファイルの現状コード（指摘箇所を含む関連部分または全文）を Read ツールで取得し、`$FILE_CONTEXT` として保持する。

既存返信の有無（stale 判定）: ステップ 2 で収集済みの返信済み ID リストを参照する。

### 3-3. Codex 監査の実行

```bash
MAGI_TMPDIR=$(mktemp -d)
```

`skills/magi-common/references/codex-audit.md`（repo 内）または `~/.claude/skills/magi-common/references/codex-audit.md` を Read ツールで読み込み、記載の手順に従って Codex を呼び出す。

Codex への入力として以下を渡す:
- `$FINDING_LIST`: finding-list fence（各エントリに MAGI/human 区別を含む）
- PR diff（`gh pr diff $PR_NUM`）: diff-block fence
- `$FILE_CONTEXT`: context-block fence
- `$COMMIT_LOG`: context-block 内に含める
- 指示: 各 finding の妥当性（`valid` / `false_positive` / `needs_human`）を判定し、stale（既に対応済み）の場合は `false_positive` とすること

### 3-4. フォールバック

`AUDIT_SKIPPED`（Codex 不可）の場合は、**`AskUserQuestion` ツールを呼び出して**確認する:
- question: "⚠ Codex が利用できません。Claude 暫定判定で続行しますか？"
- options: ["はい（Claude で続行）", "いいえ（中止）"]

「はい」の場合は Claude 自身が各指摘の妥当性を判定して続行する。「いいえ」の場合は中止する。

`AUDIT_ERROR` の場合はエラー旨をユーザーに提示し、同様の確認を行う。

監査結果（`$MAGI_TMPDIR/codex-audit.json`）を保持してステップ 4 に進む。

## ステップ 4: 対応方針の確認

Codex 監査の判定を**そのままユーザーに投げない**。指摘ごとに以下の形式で要約し、`AskUserQuestion` で方針を確認する:

| 指摘 | 行 | 内容 | Codex 監査判定 |
|------|-----|------|----------------|

`AskUserQuestion` のルール:
- 1 指摘 = 1 質問
- 最大 4 指摘まで 1 ターンで質問 (ツール制限)。5 件以上あれば HIGH/MEDIUM 優先で 4 件に絞るか、2 ターンに分割
- 各選択肢は「採用 (推奨)」「却下 (推奨)」「代替案」などで 2〜4 個
- Codex 監査が明確な推奨を出している場合は「(推奨)」マークを先頭選択肢に付ける

```bash
rm -rf "$MAGI_TMPDIR"
```

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

**採否に関わらず全指摘に返信する**（人間レビュアー・MAGI 両方）。

### 返信コマンド（共通）

```bash
gh api -X POST repos/$OWNER/$REPO/pulls/$PR_NUM/comments/$COMMENT_ID/replies \
  -f body="<返信本文>" \
  --jq '.html_url'
```

### 人間レビュアーへの返信

```
@$REVIEWER_HANDLE

<日本語の返信本文>
```

### MAGI インラインコメントへの返信

MAGI 指摘（M-1, M-2...）は対応完了・却下を問わず返信する（スレッドの Resolve はユーザーが手動で行う）：

```
✅ 対応済み（$COMMIT_HASH）: <何をどう修正したか>
```

または却下の場合：

```
⏭️ 見送り: <理由を明記>
```

### 返信本文の原則（共通）

- 採用の場合: 何をどう対応したか + コミットハッシュ
- 却下の場合: 理由を明記 (技術的根拠 / 過去指摘への言及 / ユーザー意向)
- 代替案採用の場合: 元提案との違いと理由
- 日本語 (人間 reviewer が英語ネイティブなら英語可)

同一コメントに複数指摘が含まれる場合は 1 返信にまとめる。

## ステップ 10: 報告

ユーザーに以下を報告する:
- 変更内容の要約 (1〜2 行)
- コミットハッシュ
- 各返信の URL (discussion_r... のアンカー付き)

次のアクション:
- **新規 HIGH/MEDIUM 指摘が残っている場合** → `/pr-review` を再実行して次のサイクルへ
- **全指摘への返信が完了し新規指摘なし** → マージ準備完了

## 禁止事項

- ユーザー承認なしの実装開始
- Codex 監査をスキップした実装
- レビュー指摘の無視 (採用しない場合も必ず返信で理由を述べる)
- 自己返信 (自分の前回返信に対する返信は無意味)
- `main` / `master` への直接コミット
- force push

## サイクル繰り返し

このスキルは 1 サイクル分。対応・返信完了後は `/pr-review` を再実行して新規指摘の有無を確認する。新規指摘があれば再度このスキルを呼ぶ。全体として「pr-review ↔ pr-review-respond」のループで LGTM まで到達する。
