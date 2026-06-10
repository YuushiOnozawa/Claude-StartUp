---
name: sandalphon
description: MAGI SANDALPHON（実行環境・デプロイ整合性観点）でコードをレビューする。Trigger: "/sandalphon", "デプロイレビュー", "SANDALPHONでレビュー", "実行環境チェックして", "Sandalphon"
argument-hint: "<ファイルパス または差分>"
---

# SANDALPHON スキル

MAGI SANDALPHON（実行環境の番人）の観点でコードをレビューする。
Ollama `qwen3:8b` が利用可能な場合はそちらを使い、なければ Haiku にフォールバックする。

## 実行手順

### ステップ 1: レビュー対象の特定

以下の優先順位で対象を決定する：

1. ユーザーがファイルパスを指定した場合 → そのファイルをレビュー
2. 何も指定がない場合 → `git diff --staged` でステージ済み差分を取得
3. ステージ済み差分がない場合 → `git diff HEAD` で最新コミットとの差分を取得

### ステップ 2: Ollama 可否チェックと SANDALPHON の起動

```bash
ollama list 2>/dev/null | grep -q "qwen3:8b"
```

#### Ollama が使える場合

1. Read ツールで以下を読み込む（repo 内を優先、なければ `~/.claude/` を使用）：
   - `skills/sandalphon/references/review-criteria.md` または `~/.claude/skills/sandalphon/references/review-criteria.md`
   - `skills/sandalphon/references/output-format.md` または `~/.claude/skills/sandalphon/references/output-format.md`
2. 以下の構成でプロンプトを組み立てる：
   ```
   あなたは MAGI SANDALPHON です。実行環境の番人として、
   実行環境・デプロイ整合性の観点のみでコードをレビューします。

   [review-criteria.md の内容]

   [output-format.md の内容]

   ---レビュー対象---
   [差分]
   ```
3. 組み立てたプロンプトを `ollama run qwen3:8b "$PROMPT"` に渡す

#### Ollama が使えない場合（Haiku fallback）

**前提条件**: `setup.sh` で `agents/` が `~/.claude/agents/` にコピー済みであること。

ペルソナ定義を以下の優先順位で読み込む：
1. `agents/sandalphon.md`（repo 内、作業ディレクトリが Claude-StartUp の場合）
2. `~/.claude/agents/sandalphon.md`（setup.sh でデプロイ済みのもの）

さらに以下も読み込む：
- `skills/sandalphon/references/review-criteria.md` または `~/.claude/skills/sandalphon/references/review-criteria.md`
- `skills/sandalphon/references/output-format.md` または `~/.claude/skills/sandalphon/references/output-format.md`

取得したコード・差分とペルソナ定義・references の内容を合わせて `Agent(subagent_type="general-purpose", model="haiku")` に渡す。

プロンプトには以下を含める：
- `agents/sandalphon.md` の全内容（ペルソナ・レビュー手順・出力形式）
- `references/review-criteria.md` と `references/output-format.md` の内容
- レビュー対象のコード全文または差分
- ファイルパスとプロジェクトの概要（`CLAUDE.md`・`CLAUDE.local.md` があれば読み込む）
- 「上記の SANDALPHON ペルソナに従い、実行環境・デプロイ整合性の観点でレビューしてください」という指示

### ステップ 3: 結果の表示

SANDALPHON のレビュー結果をそのまま表示する。
どちらのパスを使ったか（Ollama / Haiku fallback）を冒頭に 1 行記載する。
