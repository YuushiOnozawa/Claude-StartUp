---
name: balthasar
description: MAGI BALTHASAR（設計・アーキテクチャ観点）でコードをレビューする。Trigger: "/balthasar", "設計観点でレビュー", "BALTHASARでレビュー", "設計をBALTHASARに見てもらう"
argument-hint: "<ファイルパス、PR URL、または差分>"
---

# BALTHASAR スキル

MAGI BALTHASAR（設計哲学者）の観点でコードをレビューする。
Ollama `gemma4:26b` が利用可能な場合はそちらを使い、なければ Haiku にフォールバックする。

詳細仕様は以下を参照：
- `references/review-criteria.md` — レビュー観点・重大度基準・守備範囲外
- `references/output-format.md` — 出力フォーマット

## 実行手順

### ステップ 1: レビュー対象の特定

以下の優先順位で対象を決定する：

1. ユーザーがファイルパスを指定した場合 → そのファイルをレビュー
2. 何も指定がない場合 → `git diff --staged` でステージ済み差分を取得
3. ステージ済み差分がない場合 → `git diff HEAD` で最新コミットとの差分を取得

### ステップ 2: Ollama 可否チェックと BALTHASAR の起動

```bash
ollama list 2>/dev/null | grep -q "gemma4:26b"
```

#### Ollama が使える場合

1. Read ツールで以下を優先順位で読み込む（存在する方を使用）：
   - `skills/balthasar/references/review-criteria.md`（repo 内）または `~/.claude/skills/balthasar/references/review-criteria.md`（デプロイ済み）
   - `skills/balthasar/references/output-format.md`（repo 内）または `~/.claude/skills/balthasar/references/output-format.md`（デプロイ済み）
2. 以下の構成でシステムプロンプトを組み立てる：
   ```
   あなたは MAGI BALTHASAR です。設計哲学者として、
   設計・アーキテクチャ・外部ライブラリ公開API準拠の観点のみでコードをレビューします。

   [review-criteria.md の内容をそのまま展開]

   [output-format.md の内容をそのまま展開]

   ---レビュー対象---
   [差分]
   ```
3. 組み立てたプロンプトを `ollama run gemma4:26b` に渡す

#### Ollama が使えない場合（Haiku fallback）

**前提条件**: `setup.sh` で `agents/` が `~/.claude/agents/` にコピー済みであること。

ペルソナ定義を以下の優先順位で読み込む：
1. `agents/balthasar.md`（repo 内、作業ディレクトリが Claude-StartUp の場合）
2. `~/.claude/agents/balthasar.md`（setup.sh でデプロイ済みのもの）

Read ツールで以下も優先順位で読み込む：
- `skills/balthasar/references/review-criteria.md`（repo 内）または `~/.claude/skills/balthasar/references/review-criteria.md`
- `skills/balthasar/references/output-format.md`（repo 内）または `~/.claude/skills/balthasar/references/output-format.md`

取得したコード・差分とペルソナ定義・references/ の内容を合わせて `Agent(subagent_type="general-purpose", model="haiku")` に渡す。

プロンプトには以下を含める：
- `agents/balthasar.md` の全内容（ペルソナ・人格）
- `references/review-criteria.md` の内容（レビュー観点・重大度基準）
- `references/output-format.md` の内容（出力形式）
- レビュー対象のコード全文または差分
- 「上記の BALTHASAR ペルソナに従い、設計・アーキテクチャ・外部ライブラリ公開API準拠の観点でレビューしてください」という指示

### ステップ 3: 結果の表示

BALTHASAR のレビュー結果をそのまま表示する。
どちらのパスを使ったか（Ollama / Haiku fallback）を冒頭に 1 行記載する。
