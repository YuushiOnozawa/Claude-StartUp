---
name: balthasar
description: MAGI BALTHASAR（設計・アーキテクチャ観点）でコードをレビューする。Trigger: "/balthasar", "設計観点でレビュー", "BALTHASARでレビュー", "設計をBALTHASARに見てもらう"
---

# BALTHASAR スキル

MAGI BALTHASAR（設計哲学者）の観点でコードをレビューする。

## 実行手順

### ステップ 1: レビュー対象の特定

以下の優先順位で対象を決定する：

1. ユーザーがファイルパスを指定した場合 → そのファイルをレビュー
2. 何も指定がない場合 → `git diff --staged` でステージ済み差分を取得
3. ステージ済み差分がない場合 → `git diff HEAD` で最新コミットとの差分を取得

### ステップ 2: BALTHASAR エージェントの起動

**前提条件**: `setup.sh` で `agents/` が `~/.claude/agents/` にコピー済みであること。

ペルソナ定義を以下の優先順位で読み込む：
1. `agents/balthasar.md`（repo 内、作業ディレクトリが Claude-StartUp の場合）
2. `~/.claude/agents/balthasar.md`（setup.sh でデプロイ済みのもの）

取得したコード・差分とペルソナ定義を合わせて `Agent(subagent_type="general-purpose", model="haiku")` に渡す。
（`model="haiku"` は `agents/balthasar.md` の `model: haiku` 設定に準拠）

プロンプトには以下を含める：
- `agents/balthasar.md` の全内容（ペルソナ・レビュー手順・出力形式）
- レビュー対象のコード全文または差分
- ファイルパスとプロジェクトの概要（CLAUDE.md があれば読み込む）
- 「上記のBALTHASARペルソナに従い、設計・アーキテクチャ・外部ライブラリ公開API準拠の観点でレビューしてください」という指示

### ステップ 3: 結果の表示

BALTHASAR のレビュー結果をそのまま表示する。
