---
name: melchior
description: MAGI MELCHIOR（コード品質・バグ観点）でコードをレビューする。Trigger: "/melchior", "コード品質レビュー", "MELCHIORでレビュー", "バグチェックして", "Melchior"
---

# MELCHIOR スキル

MAGI MELCHIOR（科学者）の観点でコードをレビューする。
Ollama `qwen2.5:7b` が利用可能な場合はそちらを使い、なければ Haiku にフォールバックする。

## 実行手順

### ステップ 1: レビュー対象の特定

以下の優先順位で対象を決定する：

1. ユーザーがファイルパスを指定した場合 → そのファイルをレビュー
2. 何も指定がない場合 → `git diff --staged` でステージ済み差分を取得
3. ステージ済み差分がない場合 → `git diff HEAD` で最新コミットとの差分を取得

### ステップ 2: Ollama 可否チェックと MELCHIOR の起動

Bash で以下を確認する：

```bash
ollama list 2>/dev/null | grep -q "qwen2.5:7b"
```

#### Ollama が使える場合（High スペック）

取得した差分を以下のシステムプロンプトと合わせて `ollama run qwen2.5:7b` に渡す：

```bash
printf "あなたは MAGI MELCHIOR です。バグを見逃さない実直な審査官として、コード品質・バグの観点のみでコードをレビューします。\n\nレビュー観点: バグ・ロジックエラー / エッジケース・境界値 / 副作用・競合 / リソースリーク / コード重複・複雑さ\n\n出力形式:\n## MELCHIOR レビュー（コード品質・バグ）\n### [HIGH/MEDIUM/LOW] ファイルパス:行番号 — 見出し\n説明と改善提案\n## 品質評価\n全体評価（指摘がなければ「指摘事項なし」と明記）\n\n設計・アーキテクチャ・セキュリティは守備範囲外。\n\n---レビュー対象---\n%s" "$DIFF" \
  | ollama run qwen2.5:7b
```

#### Ollama が使えない場合（Haiku fallback）

**前提条件**: `setup.sh` で `agents/` が `~/.claude/agents/` にコピー済みであること。

ペルソナ定義を以下の優先順位で読み込む：
1. `agents/melchior.md`（repo 内、作業ディレクトリが Claude-StartUp の場合）
2. `~/.claude/agents/melchior.md`（setup.sh でデプロイ済みのもの）

取得したコード・差分とペルソナ定義を合わせて `Agent(subagent_type="general-purpose", model="haiku")` に渡す。

プロンプトには以下を含める：
- `agents/melchior.md` の全内容（ペルソナ・レビュー手順・出力形式）
- レビュー対象のコード全文または差分
- ファイルパスとプロジェクトの概要（CLAUDE.md があれば読み込む）
- 「上記の MELCHIOR ペルソナに従い、コード品質・バグの観点でレビューしてください」という指示

### ステップ 3: 結果の表示

MELCHIOR のレビュー結果をそのまま表示する。
どちらのパスを使ったか（Ollama / Haiku fallback）を冒頭に 1 行記載する。
