# MAGI 共通実行手順

> ⚠ **直列実行**: 各チャンクの処理は前のチャンクが完全に完了してから開始する。複数チャンクを並列で処理してはならない。

呼び出し元 SKILL.md で定義された以下の変数を使用する:
- `$OLLAMA_MODEL` — Ollama モデル名（例: `qwen2.5-coder:7b`）
- `$PERSONA_NAME` — ペルソナ名（例: `MELCHIOR`）
- `$AGENT_PATH` — Haiku fallback 時のエージェント定義パス（例: `agents/melchior.md`）

---

## ステップ 1: レビュー対象の特定

1. ユーザーがファイルパスを指定した場合 → そのファイルをレビュー
2. 何も指定がない場合 → `git diff --staged` でステージ済み差分を取得
3. ステージ済み差分がない場合 → `git diff HEAD` で最新コミットとの差分を取得

**CASPER のみ:** 以下を追加で取得し `$CLAUDE_RULES` として保持する:
```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
CLAUDE_RULES=$(cat ~/.claude/CLAUDE.md 2>/dev/null; cat "$ROOT/CLAUDE.md" 2>/dev/null; cat "$ROOT/CLAUDE.local.md" 2>/dev/null)
```

4. ロールプレイ指示ファイルを除外する（magi-hard/fast 経由時はフィルタ済みだが、単独実行時の防御として再適用する二層構造）:
   ```bash
   DIFF=$(printf '%s\n' "$DIFF" | awk '/^diff --git/{skip=($0 ~ /SKILL\.md |CLAUDE\.md |\/agents\/.*\.md|\/references\/.*\.md/)} !skip')
   ```

5. `$DIFF` を hunk 単位に分割し、各チャンクに対してステップ 2 を実行する:
   ```bash
   CHUNK_SECTIONS=$(printf '%s' "$DIFF" | bash scripts/magi-split-hunk.sh 400)
   ```
   `=== CHUNK: <path> (<n>) ===` で区切られた各チャンクを `$CHUNK_DIFF` として取り出し、
   ステップ 2 を `$DIFF` の代わりに `$CHUNK_DIFF` を使って実行する。
   各実行結果をチャンクヘッダー付きで `$RESULT` に追記する。
   全チャンク処理後、`$RESULT` 全体をステップ 3 の出力として使用する。

---

## ステップ 2: Ollama 可否チェックと起動

```bash
ollama list 2>/dev/null | grep -q "$OLLAMA_MODEL"
```

### Ollama が使える場合

1. Read ツールで以下を読み込む（repo 内を優先、なければ絶対パスで `~/.claude/` を使用）:
   - `skills/magi-common/references/task-base.md`（repo 内）または `/home/<user>/.claude/skills/magi-common/references/task-base.md`
   - `skills/<persona>/references/task-instruction.md`（repo 内）または `/home/<user>/.claude/skills/<persona>/references/task-instruction.md`
   - `skills/<persona>/references/review-criteria.md`（repo 内）または `/home/<user>/.claude/skills/<persona>/references/review-criteria.md`
   - `skills/magi-common/references/output-format.md`（repo 内）または `/home/<user>/.claude/skills/magi-common/references/output-format.md`

2. system/prompt を分離して一時ファイルに書き出す（差分内の特殊文字によるシェル誤展開を防ぐため）:

   **system.txt（背景知識・ロール定義）:**
   ```
   [task-instruction.md の内容をそのまま展開]
   [review-criteria.md の内容をそのまま展開]
   [output-format.md の内容をそのまま展開]
   ```
   **CASPER のみ:** system.txt の末尾に以下を追加:
   ```
   ---CLAUDE.md---
   [CLAUDE_RULES の内容]
   ```

   **prompt.txt（実タスク）:**
   ```
   [task-base.md の内容をそのまま展開]

   <TASK>
   [$CHUNK_DIFF の内容]
   </TASK>
   ```

3. 一時ファイルを Ollama に渡す:
   ```bash
   bash ~/.claude/scripts/ollama-run.sh "$OLLAMA_MODEL" system.txt < prompt.txt || {
     echo "⚠ Ollama 排他ロック取得失敗。ollama プロセスを確認してください。"
     rm -f prompt.txt system.txt; exit 1
   }
   rm -f prompt.txt system.txt
   ```

### Ollama が使えない場合（Haiku fallback）

**Haiku フォールバック確認（必須）:**
Haiku にフォールバックする前に、**`AskUserQuestion` ツールを呼び出して**確認する:
- question: "⚠ Ollama が利用できません（モデル `$OLLAMA_MODEL` が見つかりません）。Claude Haiku にフォールバックしてよいですか？"
- options: ["はい（Haiku で続行）", "いいえ（中止）"]
「いいえ」の場合はレビューを中止し、「Ollama を確認して再実行してください」と案内する。

**前提条件**: `setup.sh` で `agents/` が `~/.claude/agents/` にコピー済みであること。

エージェント定義の読み込み（以下の順で試みる）:
1. `$AGENT_PATH`（repo 内: `agents/<persona>.md`）
2. `/home/<user>/.claude/agents/<persona>.md`（setup.sh でデプロイ済みのもの）

Read ツールで以下も読み込む（repo 内を優先、なければ絶対パスで `~/.claude/` を使用）:
- `skills/magi-common/references/task-base.md`
- `skills/<persona>/references/task-instruction.md`
- `skills/<persona>/references/review-criteria.md`
- `skills/magi-common/references/output-format.md`

取得したコード・差分とペルソナ定義・references/ の内容を合わせて `Agent(subagent_type="general-purpose", model="haiku")` に渡す:
- `agents/<persona>.md` の全内容（ペルソナ・人格）
- `skills/magi-common/references/task-base.md` の内容（共通タスク指示）
- `skills/<persona>/references/task-instruction.md` の内容（ロール定義・few-shot例）
- `skills/<persona>/references/review-criteria.md` の内容（レビュー観点・重大度基準）
- `skills/magi-common/references/output-format.md` の内容（出力形式）
- 「上記の $PERSONA_NAME ペルソナに従い、担当観点でレビューしてください」という指示

**CASPER のみ:** エージェントへの指示に以下を追加:
> CLAUDE.md 群の読み込みは agents/casper.md のステップ 1 で CASPER 自身が行う（`~/.claude/CLAUDE.md`、`./CLAUDE.md`、`./CLAUDE.local.md`）。

---

## ステップ 3: 結果の表示

$PERSONA_NAME のレビュー結果をそのまま表示する。
どちらのパスを使ったか（Ollama / Haiku fallback）を冒頭に 1 行記載する。
ローカルLLMが英語で出力した場合でも、Claude が日本語に翻訳してユーザーに提示する。
