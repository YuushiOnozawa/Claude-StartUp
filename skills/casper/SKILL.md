---
name: casper
description: MAGI CASPER（CLAUDE.md準拠・ルール遵守観点）でコードをレビューする。Trigger: "/casper", "ルール遵守チェック", "CASPERでレビュー", "CLAUDE.md準拠チェック"
argument-hint: "<ファイルパス、PR URL、または差分>"
---

# CASPER スキル

MAGI CASPER（ルールの番人）の観点でコードをレビューする。
Ollama `llama3.1:8b` が利用可能な場合はそちらを使い、なければ Haiku にフォールバックする。

詳細仕様は以下を参照：
- `references/review-criteria.md` — レビュー観点・重大度基準・守備範囲外
- `references/output-format.md` — 出力フォーマット

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

1. Read ツールで以下を優先順位で読み込む（存在する方を使用）：
   - `skills/casper/references/review-criteria.md`（repo 内）または `~/.claude/skills/casper/references/review-criteria.md`（デプロイ済み）
   - `skills/casper/references/output-format.md`（repo 内）または `~/.claude/skills/casper/references/output-format.md`（デプロイ済み）
2. 以下の構成でシステムプロンプトを組み立てる：
   ```
   あなたは MAGI CASPER です。ルールの番人として、
   コードが定められたルールと規約に準拠しているかを評価します。

   [review-criteria.md の内容をそのまま展開]

   [output-format.md の内容をそのまま展開]

   ---CLAUDE.md---
   [CLAUDE_RULES の内容]

   ---レビュー対象---
   [差分]
   ```
3. 組み立てたプロンプトを `ollama run llama3.1:8b` に渡す

#### Ollama が使えない場合（Haiku fallback）

**前提条件**: `setup.sh` で `agents/` が `~/.claude/agents/` にコピー済みであること。

ペルソナ定義を以下の優先順位で読み込む：
1. `agents/casper.md`（repo 内、作業ディレクトリが Claude-StartUp の場合）
2. `~/.claude/agents/casper.md`（setup.sh でデプロイ済みのもの）

Read ツールで以下も優先順位で読み込む：
- `skills/casper/references/review-criteria.md`（repo 内）または `~/.claude/skills/casper/references/review-criteria.md`
- `skills/casper/references/output-format.md`（repo 内）または `~/.claude/skills/casper/references/output-format.md`

取得したコード・差分とペルソナ定義・references/ の内容を合わせて `Agent(subagent_type="general-purpose", model="haiku")` に渡す。

プロンプトには以下を含める：
- `agents/casper.md` の全内容（ペルソナ・人格）
- `references/review-criteria.md` の内容（レビュー観点・重大度基準）
- `references/output-format.md` の内容（出力形式）
- レビュー対象のコード全文または差分
- 「上記の CASPER ペルソナに従い、CLAUDE.md 準拠・ルール遵守の観点でレビューしてください」という指示

**注:** CLAUDE.md 群の読み込みは agents/casper.md のステップ 1 で CASPER 自身が行う（`~/.claude/CLAUDE.md`、`./CLAUDE.md`、`./CLAUDE.local.md`）。プロンプトへの直接埋め込み不要。

### ステップ 3: 結果の表示

CASPER のレビュー結果をそのまま表示する。
どちらのパスを使ったか（Ollama / Haiku fallback）を冒頭に 1 行記載する。
