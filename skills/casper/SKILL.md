---
name: casper
description: MAGI CASPER（CLAUDE.md準拠・ルール遵守観点）でコードをレビューする。Trigger: "/casper", "ルール遵守チェック", "CASPERでレビュー", "CLAUDE.md準拠チェック"
argument-hint: "<ファイルパス または差分>"
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

取得した `DIFF` から `.md` ファイルを除外する（ローカルLLMへのロールプレイ指示混入防止）：
```bash
DIFF=$(printf '%s\n' "$DIFF" | awk '/^diff --git/{skip=($0 ~ /SKILL\.md |CLAUDE\.md |\/agents\/[^ ]*\.md |\/references\/[^ ]*\.md /)} !skip')
```

### ステップ 2: Ollama 可否チェックと CASPER の起動

```bash
ollama list 2>/dev/null | grep -q "llama3.1:8b"
```

#### Ollama が使える場合

1. Read ツールで以下を優先順位で読み込む（`~` は展開不可のため絶対パスで指定）：
   - `skills/casper/references/review-criteria.md`（repo 内）または `/home/<user>/.claude/skills/casper/references/review-criteria.md`（デプロイ済み）
   - `skills/casper/references/output-format.md`（repo 内）または `/home/<user>/.claude/skills/casper/references/output-format.md`（デプロイ済み）
2. 以下の構成でシステムプロンプトを一時ファイル `prompt.txt` に書き出す（差分・ルール内の特殊文字によるシェル誤展開を防ぐため）：
   ```
   [review-criteria.md の内容をそのまま展開]

   [output-format.md の内容をそのまま展開]

   ---CLAUDE.md---
   [CLAUDE_RULES の内容]

   ---レビュー対象---
   [差分]
   ```
3. 一時ファイルを Ollama に渡す：
   ```bash
   bash ~/.claude/scripts/ollama-run.sh llama3.1:8b < prompt.txt || {
     echo "⚠ Ollama 排他ロック取得失敗。ollama プロセスを確認してください。"
     rm -f prompt.txt; exit 1
   }
   rm prompt.txt
   ```

#### Ollama が使えない場合（Haiku fallback）

**Haiku フォールバック確認（必須）:**
Haiku にフォールバックする前に、ユーザーに必ず確認する：
「⚠ Ollama が利用できません（モデル `llama3.1:8b` が見つかりません）。Claude Haiku にフォールバックしてよいですか？」
ユーザーが拒否した場合はレビューを中止し、「Ollama を確認して再実行してください」と案内する。

**前提条件**: `setup.sh` で `agents/` が `~/.claude/agents/` にコピー済みであること。

ペルソナ定義を以下の優先順位で読み込む：
1. `agents/casper.md`（repo 内、作業ディレクトリが Claude-StartUp の場合）
2. `~/.claude/agents/casper.md`（setup.sh でデプロイ済みのもの）

Read ツールで以下も優先順位で読み込む（`~` は展開不可のため絶対パスで指定）：
- `skills/casper/references/review-criteria.md`（repo 内）または `/home/<user>/.claude/skills/casper/references/review-criteria.md`
- `skills/casper/references/output-format.md`（repo 内）または `/home/<user>/.claude/skills/casper/references/output-format.md`

取得したコード・差分とペルソナ定義・references/ の内容を合わせて `Agent(subagent_type="general-purpose", model="haiku")` に渡す。

プロンプトには以下を含める：
- `agents/casper.md` の全内容（ペルソナ・人格）
- `skills/casper/references/review-criteria.md` の内容（レビュー観点・重大度基準）
- `skills/casper/references/output-format.md` の内容（出力形式）
- レビュー対象のコード全文または差分
- 「上記の CASPER ペルソナに従い、CLAUDE.md 準拠・ルール遵守の観点でレビューしてください」という指示

**注:** CLAUDE.md 群の読み込みは agents/casper.md のステップ 1 で CASPER 自身が行う（`~/.claude/CLAUDE.md`、`./CLAUDE.md`、`./CLAUDE.local.md`）。プロンプトへの直接埋め込み不要。

### ステップ 3: 結果の表示

CASPER のレビュー結果をそのまま表示する。
どちらのパスを使ったか（Ollama / Haiku fallback）を冒頭に 1 行記載する。
ローカルLLMが英語で出力した場合でも、Claude が日本語に翻訳してユーザーに提示する。
