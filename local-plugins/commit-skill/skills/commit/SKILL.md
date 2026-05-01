---
name: commit
description: Git commit workflow skill. Use this skill EVERY TIME the user asks to commit, create a commit, record changes, or save to git history. Never run git commit directly — always use this skill instead. Handles staging, commit message drafting, and Co-Authored-By attribution. Trigger on: "コミット", "commit", "変更を保存", "git に保存", "コミットして", or any request to record code changes.
---

# Commit Skill

`git commit` を直接実行せず、このスキルを通じてコミットを作成する。

## ステップ 1: 事前チェック

まず現在のブランチを確認する：

```bash
git branch --show-current
```

**`main` または `master` ブランチへの直接コミットは禁止。** 該当する場合は中断してユーザーに伝える。

## ステップ 2: 現状把握（並列実行）

以下を同時に実行する：
- `git status` — 変更ファイルの一覧（`-uall` は使わない）
- `git diff` — ステージ済み・未ステージ両方の差分
- `git log --oneline -10` — 直近のコミットメッセージのスタイル確認

## ステップ 3: コミットメッセージの作成

### Conventional Commits 形式（必須）

```
<type>(<scope>): <日本語の説明>

<本文（任意）>

Co-Authored-By: Claude <noreply@anthropic.com>
```

**type の選択肢：** `feat` / `fix` / `docs` / `style` / `refactor` / `test` / `chore` / `perf` / `ci` / `build` / `revert`

**日本語の強制ルール：**
- タイトル（subject）は日本語で書く
- 本文を書く場合も日本語で書く
- type と scope は英語のまま（仕様上変更不可）

**例：**
- `feat(auth): JWTによる認証を実装`
- `fix(api): レスポンスが空になるバグを修正`
- `chore(deps): 依存パッケージを更新`

**その他のルール：**
- 変更の「何を」ではなく「なぜ」を中心に書く
- **1コミット = 1つの関心事**。混在している場合は分割を提案する
- 機密ファイル（`.env`、認証情報など）が含まれていたら警告して中断する

## ステップ 4: ステージングとコミット

`git add -A` や `git add .` は使わず、ファイルを個別に指定する。

コミットメッセージは必ず HEREDOC で渡す：

```bash
git commit -m "$(cat <<'EOF'
feat(scope): 日本語の説明

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

コミット後に `git status` で最終確認する。

> CommitLint 等の検証は git hooks（commit-msg フック）に委ねる。このスキルでは実行しない。

## 禁止事項

- `main` / `master` への直接コミット
- `--no-verify`（フックのスキップ）
- `--amend`（ユーザーが明示的に要求した場合のみ許可）
- `main` / `master` への force push
- コミット後の自動 push（ユーザーが明示的に要求した場合のみ）
- 英語のコミットタイトル・本文（type/scope を除く）
