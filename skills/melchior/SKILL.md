---
name: melchior
description: MAGI MELCHIOR（コード品質・バグ観点）でコードをレビューする。Trigger: "/melchior", "コード品質レビュー", "MELCHIORでレビュー", "バグチェックして", "Melchior"
argument-hint: "<ファイルパス または差分>"
---

# MELCHIOR スキル

MAGI MELCHIOR（科学者）の観点でコードをレビューする。
Ollama `qwen2.5-coder:7b` が利用可能な場合はそちらを使い、なければ Haiku にフォールバックする。

詳細仕様は以下を参照：
- `references/review-criteria.md` — レビュー観点・重大度基準・守備範囲外
- `references/output-format.md` — 出力フォーマット

## 実行手順

### ステップ 1: レビュー対象の特定

以下の優先順位で対象を決定する：

1. ユーザーがファイルパスを指定した場合 → そのファイルをレビュー
2. 何も指定がない場合 → `git diff --staged` でステージ済み差分を取得
3. ステージ済み差分がない場合 → `git diff HEAD` で最新コミットとの差分を取得

### ステップ 2: Ollama 可否チェックと MELCHIOR の起動

Bash で以下を確認する：

```bash
ollama list 2>/dev/null | grep -q "qwen2.5-coder:7b"
```

#### Ollama が使える場合（High スペック）

1. Read ツールで以下を読み込む（repo 内を優先、なければ絶対パスで `~/.claude/` を使用）：
   - `skills/melchior/references/review-criteria.md`（repo 内）または `/home/<user>/.claude/skills/melchior/references/review-criteria.md`（`~` は展開不可のため絶対パスで指定）
   - `skills/melchior/references/output-format.md`（repo 内）または `/home/<user>/.claude/skills/melchior/references/output-format.md`
2. 以下の構成でシステムプロンプトを組み立てる：
   ```
   [review-criteria.md の内容をそのまま展開]

   [output-format.md の内容をそのまま展開]

   ---レビュー対象---
   [差分]
   ```
3. 組み立てたプロンプトを Ollama に渡す：
   ```bash
   printf '%s' "$PROMPT" | bash ~/.claude/scripts/ollama-run.sh qwen2.5-coder:7b || {
     echo "⚠ Ollama 排他ロック取得失敗。ollama プロセスを確認してください。"
     exit 1
   }
   ```

#### Ollama が使えない場合（Haiku fallback）

**Haiku フォールバック確認（必須）:**
Haiku にフォールバックする前に、ユーザーに必ず確認する：
「⚠ Ollama が利用できません（モデル `qwen2.5-coder:7b` が見つかりません）。Claude Haiku にフォールバックしてよいですか？」
ユーザーが拒否した場合はレビューを中止し、「Ollama を確認して再実行してください」と案内する。

**前提条件**: `setup.sh` で `agents/` が `~/.claude/agents/` にコピー済みであること。

ペルソナ定義を以下の優先順位で読み込む：
1. `agents/melchior.md`（repo 内、作業ディレクトリが Claude-StartUp の場合）
2. `~/.claude/agents/melchior.md`（setup.sh でデプロイ済みのもの）

Read ツールで以下も読み込む（repo 内を優先、なければ絶対パスで `~/.claude/` を使用）：
- `skills/melchior/references/review-criteria.md`（repo 内）または `/home/<user>/.claude/skills/melchior/references/review-criteria.md`
- `skills/melchior/references/output-format.md`（repo 内）または `/home/<user>/.claude/skills/melchior/references/output-format.md`

取得したコード・差分とペルソナ定義・references/ の内容を合わせて `Agent(subagent_type="general-purpose", model="haiku")` に渡す。

プロンプトには以下を含める：
- `agents/melchior.md` の全内容（ペルソナ・人格）
- `skills/melchior/references/review-criteria.md` の内容（レビュー観点・重大度基準）
- `skills/melchior/references/output-format.md` の内容（出力形式）
- レビュー対象のコード全文または差分
- 「上記の MELCHIOR ペルソナに従い、コード品質・バグの観点でレビューしてください」という指示

### ステップ 3: 結果の表示

MELCHIOR のレビュー結果をそのまま表示する。
どちらのパスを使ったか（Ollama / Haiku fallback）を冒頭に 1 行記載する。
ローカルLLMが英語で出力した場合でも、Claude が日本語に翻訳してユーザーに提示する。
