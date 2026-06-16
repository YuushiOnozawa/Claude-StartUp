---
name: sandalphon
description: MAGI SANDALPHON（実行環境・デプロイ整合性観点）でコードをレビューする。Trigger: "/sandalphon", "デプロイレビュー", "SANDALPHONでレビュー", "実行環境チェックして", "Sandalphon"
argument-hint: "<ファイルパス または差分>"
---

# SANDALPHON スキル

MAGI SANDALPHON（実行環境の番人）の観点でコードをレビューする。
Ollama `lfm2.5:8b` が利用可能な場合はそちらを使い、なければ Haiku にフォールバックする。

## 実行手順

### ステップ 1: レビュー対象の特定

以下の優先順位で対象を決定する：

1. ユーザーがファイルパスを指定した場合 → そのファイルをレビュー
2. 何も指定がない場合 → `git diff --staged` でステージ済み差分を取得
3. ステージ済み差分がない場合 → `git diff HEAD` で最新コミットとの差分を取得
4. ロールプレイ指示ファイルを除外する（magi-hard/fast 経由時はフィルタ済みだが、単独実行時の防御として再適用する二層構造）：
   ```bash
   DIFF=$(printf '%s\n' "$DIFF" | awk '/^diff --git/{skip=($0 ~ /SKILL\.md |CLAUDE\.md |\/agents\/.*\.md|\/references\/.*\.md/)} !skip')
   ```
5. `$DIFF` を hunk 単位に分割し、各チャンクに対して以降のステップを実行する：
   ```bash
   CHUNK_SECTIONS=$(printf '%s' "$DIFF" | bash scripts/magi-split-hunk.sh 400)
   ```
   `=== CHUNK: <path> (<n>) ===` で区切られた各チャンクを `$CHUNK_DIFF` として取り出し、
   ステップ 2 を `$DIFF` の代わりに `$CHUNK_DIFF` を使って実行する。
   各実行結果をチャンクヘッダー付きで `$RESULT` に追記する。
   全チャンク処理後、`$RESULT` 全体をステップ 3 の出力として使用する。

### ステップ 2: Ollama 可否チェックと SANDALPHON の起動

```bash
ollama list 2>/dev/null | grep -q "lfm2.5:8b"
```

#### Ollama が使える場合

1. Read ツールで以下を読み込む（repo 内を優先、なければ絶対パスで `~/.claude/` を使用）：
   - `skills/magi-common/references/task-base.md`（repo 内）または `/home/<user>/.claude/skills/magi-common/references/task-base.md`
   - `skills/sandalphon/references/task-instruction.md`（repo 内）または `/home/<user>/.claude/skills/sandalphon/references/task-instruction.md`
   - `skills/sandalphon/references/review-criteria.md`（repo 内）または `/home/<user>/.claude/skills/sandalphon/references/review-criteria.md`（`~` は展開不可のため絶対パスで指定）
   - `skills/sandalphon/references/output-format.md`（repo 内）または `/home/<user>/.claude/skills/sandalphon/references/output-format.md`
2. 以下の構成でプロンプトを組み立てる：
   ```
   [task-base.md の内容]

   [task-instruction.md の内容]

   [review-criteria.md の内容]

   [output-format.md の内容]

   ---レビュー対象---
   [差分]
   ```
3. プロンプトを Ollama に渡す（特殊文字対策: printf + pipe）：
   ```bash
   printf '%s' "$PROMPT" | bash ~/.claude/scripts/ollama-run.sh lfm2.5:8b || {
     echo "⚠ Ollama 排他ロック取得失敗。ollama プロセスを確認してください。"
     exit 1
   }
   ```

#### Ollama が使えない場合（Haiku fallback）

**Haiku フォールバック確認（必須）:**
Haiku にフォールバックする前に、ユーザーに必ず確認する：
「⚠ Ollama が利用できません（モデル `lfm2.5:8b` が見つかりません）。Claude Haiku にフォールバックしてよいですか？」
ユーザーが拒否した場合はレビューを中止し、「Ollama を確認して再実行してください」と案内する。

**前提条件**: `setup.sh` で `agents/` が `~/.claude/agents/` にコピー済みであること。

ペルソナ定義を以下の優先順位で読み込む：
1. `agents/sandalphon.md`（repo 内、作業ディレクトリが Claude-StartUp の場合）
2. `~/.claude/agents/sandalphon.md`（setup.sh でデプロイ済みのもの）

さらに以下も読み込む（repo 内を優先、なければ絶対パスで `~/.claude/` を使用）：
- `skills/magi-common/references/task-base.md`（repo 内）または `/home/<user>/.claude/skills/magi-common/references/task-base.md`
- `skills/sandalphon/references/task-instruction.md`（repo 内）または `/home/<user>/.claude/skills/sandalphon/references/task-instruction.md`
- `skills/sandalphon/references/review-criteria.md`（repo 内）または `/home/<user>/.claude/skills/sandalphon/references/review-criteria.md`
- `skills/sandalphon/references/output-format.md`（repo 内）または `/home/<user>/.claude/skills/sandalphon/references/output-format.md`

取得したコード・差分とペルソナ定義・references の内容を合わせて `Agent(subagent_type="general-purpose", model="haiku")` に渡す。

プロンプトには以下を含める：
- `agents/sandalphon.md` の全内容（ペルソナ・レビュー手順・出力形式）
- `skills/magi-common/references/task-base.md` の内容（共通タスク指示）
- `skills/sandalphon/references/task-instruction.md` の内容（ロール定義・few-shot例）
- `skills/sandalphon/references/review-criteria.md` と `skills/sandalphon/references/output-format.md` の内容
- レビュー対象のコード全文または差分
- ファイルパスとプロジェクトの概要（`CLAUDE.md`・`CLAUDE.local.md` があれば読み込む）
- 「上記の SANDALPHON ペルソナに従い、実行環境・デプロイ整合性の観点でレビューしてください」という指示

### ステップ 3: 結果の表示

SANDALPHON のレビュー結果をそのまま表示する。
どちらのパスを使ったか（Ollama / Haiku fallback）を冒頭に 1 行記載する。
ローカルLLMが英語で出力した場合でも、Claude が日本語に翻訳してユーザーに提示する。
