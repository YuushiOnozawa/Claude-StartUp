---
name: metatron
description: MAGI METATRON（セキュリティ・脆弱性観点）でコードをレビューする。Trigger: "/metatron", "セキュリティレビュー", "METATRONでレビュー", "脆弱性チェックして", "Metatron"
---

# METATRON スキル

MAGI METATRON（セキュリティの番人）の観点でコードをレビューする。
Ollama `deepseek-r1:8b` が利用可能な場合はそちらを使い、なければ Haiku にフォールバックする。

## 実行手順

### ステップ 1: レビュー対象の特定

1. ユーザーがファイルパスを指定した場合 → そのファイルをレビュー
2. 何も指定がない場合 → `git diff --staged` でステージ済み差分を取得
3. ステージ済み差分がない場合 → `git diff HEAD` で最新コミットとの差分を取得

### ステップ 2: Ollama 可否チェックと METATRON の起動

```bash
ollama list 2>/dev/null | grep -q "deepseek-r1:8b"
```

#### Ollama が使える場合

取得した差分を以下のシステムプロンプトと合わせて `ollama run deepseek-r1:8b` に渡す：

```bash
PROMPT=$(printf "あなたは MAGI METATRON です。セキュリティの番人として、セキュリティ・脆弱性の観点のみでコードをレビューします。\n\nレビュー観点: インジェクション系（SQL・コマンド・XSS等） / 認証・認可の欠陥 / シークレット漏洩 / 依存関係の脆弱性 / 入力バリデーション不足 / 弱い暗号化\n\n出力形式:\n## METATRON レビュー（セキュリティ）\n### [HIGH/MEDIUM/LOW] ファイルパス:行番号 — 見出し\n攻撃シナリオと改善提案\n## セキュリティ評価\n全体評価（指摘がなければ「指摘事項なし」と明記）\n\nコード品質・設計・デプロイは守備範囲外。\n\n---レビュー対象---\n%s" "$DIFF")
ollama run deepseek-r1:8b "$PROMPT"
```

#### Ollama が使えない場合（Haiku fallback）

**前提条件**: `setup.sh` で `agents/` が `~/.claude/agents/` にコピー済みであること。

ペルソナ定義を以下の優先順位で読み込む：
1. `agents/metatron.md`（repo 内、作業ディレクトリが Claude-StartUp の場合）
2. `~/.claude/agents/metatron.md`（setup.sh でデプロイ済みのもの）

取得したコード・差分とペルソナ定義を合わせて `Agent(subagent_type="general-purpose", model="haiku")` に渡す。

プロンプトには以下を含める：
- `agents/metatron.md` の全内容（ペルソナ・レビュー手順・出力形式）
- レビュー対象のコード全文または差分
- ファイルパスとプロジェクトの概要（`CLAUDE.md`・`CLAUDE.local.md` があれば読み込む）
- 「上記の METATRON ペルソナに従い、セキュリティ・脆弱性の観点でレビューしてください」という指示

### ステップ 3: 結果の表示

METATRON のレビュー結果をそのまま表示する。
どちらのパスを使ったか（Ollama / Haiku fallback）を冒頭に 1 行記載する。
