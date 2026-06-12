---
name: metatron
description: MAGI METATRON（セキュリティ・脆弱性観点）でコードをレビューする。Trigger: "/metatron", "セキュリティレビュー", "METATRONでレビュー", "脆弱性チェックして", "Metatron"
argument-hint: "<ファイルパス または差分>"
---

# METATRON スキル

MAGI METATRON（セキュリティの番人）の観点でコードをレビューする。
Ollama `deepseek-r1:8b` が利用可能な場合はそちらを使い、なければ Haiku にフォールバックする。

## 実行手順

### ステップ 1: レビュー対象の特定

以下の優先順位で対象を決定する：

1. ユーザーがファイルパスを指定した場合 → そのファイルをレビュー
2. 何も指定がない場合 → `git diff --staged` でステージ済み差分を取得
3. ステージ済み差分がない場合 → `git diff HEAD` で最新コミットとの差分を取得

### ステップ 2: Ollama 可否チェックと METATRON の起動

```bash
ollama list 2>/dev/null | grep -q "deepseek-r1:8b"
```

#### Ollama が使える場合

1. Read ツールで以下を読み込む（repo 内を優先、なければ絶対パスで `~/.claude/` を使用）：
   - `skills/metatron/references/review-criteria.md`（repo 内）または `/home/<user>/.claude/skills/metatron/references/review-criteria.md`（`~` は展開不可のため絶対パスで指定）
   - `skills/metatron/references/output-format.md`（repo 内）または `/home/<user>/.claude/skills/metatron/references/output-format.md`
2. 以下の構成でプロンプトを組み立てる：
   ```
   [review-criteria.md の内容]

   [output-format.md の内容]

   ---レビュー対象---
   [差分]
   ```
3. プロンプトを一時ファイル経由で Ollama に渡す（特殊文字対策 + 排他ロック）：
   ```bash
   # stale lock チェック（Ollama プロセスが存在しない場合はロックを解放）
   [ -f /tmp/magi-ollama.lock ] && ! pgrep -x ollama > /dev/null 2>&1 && rm -f /tmp/magi-ollama.lock
   # プロンプトを一時ファイルに書き出し
   printf '%s' "$PROMPT" > /tmp/magi-deepseek-prompt.txt
   # タイムアウト付きロック取得（最大5分）
   flock -w 300 /tmp/magi-ollama.lock ollama run deepseek-r1:8b < /tmp/magi-deepseek-prompt.txt || {
     echo "⚠ Ollama ロック取得タイムアウト（5分）。他のプロセスが実行中か確認してください。"
     rm -f /tmp/magi-deepseek-prompt.txt; exit 1
   }
   rm /tmp/magi-deepseek-prompt.txt
   ```

#### Ollama が使えない場合（Haiku fallback）

**Haiku フォールバック確認（必須）:**
Haiku にフォールバックする前に、ユーザーに必ず確認する：
「⚠ Ollama が利用できません（モデル `deepseek-r1:8b` が見つかりません）。Claude Haiku にフォールバックしてよいですか？」
ユーザーが拒否した場合はレビューを中止し、「Ollama を確認して再実行してください」と案内する。

**前提条件**: `setup.sh` で `agents/` が `~/.claude/agents/` にコピー済みであること。

ペルソナ定義を以下の優先順位で読み込む：
1. `agents/metatron.md`（repo 内、作業ディレクトリが Claude-StartUp の場合）
2. `~/.claude/agents/metatron.md`（setup.sh でデプロイ済みのもの）

さらに以下も読み込む（repo 内を優先、なければ絶対パスで `~/.claude/` を使用）：
- `skills/metatron/references/review-criteria.md`（repo 内）または `/home/<user>/.claude/skills/metatron/references/review-criteria.md`
- `skills/metatron/references/output-format.md`（repo 内）または `/home/<user>/.claude/skills/metatron/references/output-format.md`

取得したコード・差分とペルソナ定義・references の内容を合わせて `Agent(subagent_type="general-purpose", model="haiku")` に渡す。

プロンプトには以下を含める：
- `agents/metatron.md` の全内容（ペルソナ・レビュー手順・出力形式）
- `skills/metatron/references/review-criteria.md` と `skills/metatron/references/output-format.md` の内容
- レビュー対象のコード全文または差分
- ファイルパスとプロジェクトの概要（`CLAUDE.md`・`CLAUDE.local.md` があれば読み込む）
- 「上記の METATRON ペルソナに従い、セキュリティ・脆弱性の観点でレビューしてください」という指示

### ステップ 3: 結果の表示

METATRON のレビュー結果をそのまま表示する。
どちらのパスを使ったか（Ollama / Haiku fallback）を冒頭に 1 行記載する。
ローカルLLMが英語で出力した場合でも、Claude が日本語に翻訳してユーザーに提示する。
