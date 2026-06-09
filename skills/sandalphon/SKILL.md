---
name: sandalphon
description: MAGI SANDALPHON（実行環境・デプロイ整合性観点）でコードをレビューする。Trigger: "/sandalphon", "デプロイレビュー", "SANDALPHONでレビュー", "実行環境チェックして", "Sandalphon"
---

# SANDALPHON スキル

MAGI SANDALPHON（実行環境の番人）の観点でコードをレビューする。
Ollama `qwen3:8b` が利用可能な場合はそちらを使い、なければ Haiku にフォールバックする。

## 実行手順

### ステップ 1: レビュー対象の特定

1. ユーザーがファイルパスを指定した場合 → そのファイルをレビュー
2. 何も指定がない場合 → `git diff --staged` でステージ済み差分を取得
3. ステージ済み差分がない場合 → `git diff HEAD` で最新コミットとの差分を取得

### ステップ 2: Ollama 可否チェックと SANDALPHON の起動

```bash
ollama list 2>/dev/null | grep -q "qwen3:8b"
```

#### Ollama が使える場合

取得した差分を以下のシステムプロンプトと合わせて `ollama run qwen3:8b` に渡す：

```bash
PROMPT=$(printf "あなたは MAGI SANDALPHON です。実行環境の番人として、実行環境・デプロイ整合性の観点のみでコードをレビューします。\n\nレビュー観点: デプロイ時の破壊的変更 / 環境変数・設定ファイルの整合性 / マイグレーションの安全性 / CI/CDパイプラインへの影響 / ロールバック可能性 / 依存関係バージョン互換性\n\n出力形式:\n## SANDALPHON レビュー（実行環境・デプロイ）\n### [HIGH/MEDIUM/LOW] ファイルパス:行番号 — 見出し\nリスクシナリオと改善提案\n## デプロイ評価\n全体評価（指摘がなければ「指摘事項なし」と明記）\n\nコード品質・バグ・セキュリティは守備範囲外。\n\n---レビュー対象---\n%s" "$DIFF")
ollama run qwen3:8b "$PROMPT"
```

#### Ollama が使えない場合（Haiku fallback）

**前提条件**: `setup.sh` で `agents/` が `~/.claude/agents/` にコピー済みであること。

ペルソナ定義を以下の優先順位で読み込む：
1. `agents/sandalphon.md`（repo 内、作業ディレクトリが Claude-StartUp の場合）
2. `~/.claude/agents/sandalphon.md`（setup.sh でデプロイ済みのもの）

取得したコード・差分とペルソナ定義を合わせて `Agent(subagent_type="general-purpose", model="haiku")` に渡す。

プロンプトには以下を含める：
- `agents/sandalphon.md` の全内容（ペルソナ・レビュー手順・出力形式）
- レビュー対象のコード全文または差分
- ファイルパスとプロジェクトの概要（CLAUDE.md があれば読み込む）
- 「上記の SANDALPHON ペルソナに従い、実行環境・デプロイ整合性の観点でレビューしてください」という指示

### ステップ 3: 結果の表示

SANDALPHON のレビュー結果をそのまま表示する。
どちらのパスを使ったか（Ollama / Haiku fallback）を冒頭に 1 行記載する。
