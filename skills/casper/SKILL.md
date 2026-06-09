---
name: casper
description: MAGI CASPER（CLAUDE.md準拠・ルール遵守観点）でコードをレビューする。Trigger: "/casper", "ルール遵守チェック", "CASPERでレビュー", "CLAUDE.md準拠チェック"
---

# CASPER スキル

MAGI CASPER（ルールの番人）の観点でコードをレビューする。
Ollama `llama3.1:8b` が利用可能な場合はそちらを使い、なければ Haiku にフォールバックする。

## 実行手順

### ステップ 1: レビュー対象と CLAUDE.md の取得

以下を並列で取得する：

- **差分 (`DIFF`)**: ユーザー指定のファイルがあればその内容、なければ `git diff --staged`（空なら `git diff HEAD`）
- **ルール (`CLAUDE_RULES`)** (Ollama パス用):
  ```bash
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
  CLAUDE_RULES=$(cat ~/.claude/CLAUDE.md 2>/dev/null; cat "$ROOT/CLAUDE.md" 2>/dev/null; cat "$ROOT/CLAUDE.local.md" 2>/dev/null)
  ```

### ステップ 2: Ollama 可否チェックと CASPER の起動

```bash
ollama list 2>/dev/null | grep -q "llama3.1:8b"
```

#### Ollama が使える場合

取得した差分と CLAUDE.md の内容を合わせて stdin 経由で `ollama run llama3.1:8b` に渡す：

```bash
printf "あなたは MAGI CASPER です。ルールの番人として、コードが定められたルールと規約に準拠しているかを評価します。\n\n人格: 例外を認めないルールの番人。CLAUDE.md と決め事への逸脱を絶対に見逃さない。「なんとなくOK」は存在しない。\n\nレビュー観点:\n1. CLAUDE.md の行動原則への準拠（シンプル第一・影響最小化・根本原因への対処）\n2. コードスタイルの一貫性（周辺コードとの整合）\n3. 禁止事項（--no-verify 等の禁止操作・コマンドインジェクション等のセキュリティ問題）\n4. 外部ライブラリの公開APIのみを使用しているか（内部実装へのアクセスがないか）\n\n出力形式:\n## CASPER レビュー（ルール遵守）\n### [HIGH/MEDIUM/LOW] ファイルパス:行番号 — 見出し\nどのルールに違反しているかを明記して説明。\n## 遵守状況\n全体評価（指摘がなければ「指摘事項なし」と明記する）\n\n---CLAUDE.md---\n%s\n\n---レビュー対象---\n%s" "$CLAUDE_RULES" "$DIFF" \
  | ollama run llama3.1:8b
```

#### Ollama が使えない場合（Haiku fallback）

**前提条件**: `setup.sh` で `agents/` が `~/.claude/agents/` にコピー済みであること。

ペルソナ定義を以下の優先順位で読み込む：
1. `agents/casper.md`（repo 内、作業ディレクトリが Claude-StartUp の場合）
2. `~/.claude/agents/casper.md`（setup.sh でデプロイ済みのもの）

取得したコード・差分とペルソナ定義を合わせて `Agent(subagent_type="general-purpose", model="haiku")` に渡す。

プロンプトには以下を含める：
- `agents/casper.md` の全内容（ペルソナ・レビュー手順・出力形式）
- レビュー対象のコード全文または差分
- 「上記の CASPER ペルソナに従い、CLAUDE.md 準拠・ルール遵守の観点でレビューしてください」という指示

**注:** CLAUDE.md 群の読み込みは agents/casper.md のステップ 1 で CASPER 自身が行う（`~/.claude/CLAUDE.md`、`./CLAUDE.md`、`./CLAUDE.local.md`）。プロンプトへの直接埋め込み不要。

### ステップ 3: 結果の表示

CASPER のレビュー結果をそのまま表示する。
どちらのパスを使ったか（Ollama / Haiku fallback）を冒頭に 1 行記載する。
