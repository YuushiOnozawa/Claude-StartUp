# MAGI 共通実行手順

> ⚠ **直列実行**: 各チャンクの処理は前のチャンクが完全に完了してから開始する。複数チャンクを並列で処理してはならない。

呼び出し元 SKILL.md で定義された以下の変数を使用する:
- `$OLLAMA_MODEL` — Ollama モデル名（例: `qwen2.5-coder:7b`）
- `$PERSONA_NAME` — ペルソナ名（例: `MELCHIOR`）
- `$AGENT_PATH` — Haiku fallback 時のエージェント定義パス（例: `agents/melchior.md`）
- `$OUTPUT_FORMAT_PATH`（省略可） — 出力契約ファイルのパス。省略時は `skills/magi-common/references/output-format.md`（v1・severity付き）を使う。v2ペルソナ（DETECTION NOTES契約）は `skills/magi-common/references/output-format-v2.md` を設定する
- `$MAGI_ORCHESTRATED`（省略可） — 呼び出し元が `magi-fast`/`magi-hard` 等のオーケストレーターであることを示すフラグ。**文字列 `true` との完全一致のみ有効**とする。設定されている場合、v2ペルソナは自分ではNormalizerを呼ばず生の結果を返す（呼び出し元がバッチでNormalizerを呼ぶ）。未設定（単体実行）の場合、v2ペルソナは自分でNormalizerを呼ぶ。**この変数は呼び出し元がペルソナSKILL.mdを呼ぶときにのみ設定するものであり、ペルソナ実行の内部で発生する他のサブ処理へ暗黙に引き継いではならない**（単体実行での二重Normalizer呼び出しを防ぐため）

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
   DIFF=$(printf '%s\n' "$DIFF" | bash scripts/magi-diff-filter.sh)
   ```

5. `$DIFF` を hunk 単位に分割し、各チャンクに対してステップ 2 を実行する:
   ```bash
   CHUNK_SECTIONS=$(printf '%s' "$DIFF" | bash scripts/magi-split-hunk.sh 400)
   ```
   `=== CHUNK: <path> (<n>) ===` で区切られた各チャンクを `$CHUNK_DIFF` として取り出し、
   ステップ 2 を `$DIFF` の代わりに `$CHUNK_DIFF` を使って実行する。
   各実行結果をチャンクヘッダー付きで `$RESULT` に追記する。
   全チャンク処理後、`$RESULT` 全体をステップ 3 の出力として使用する。

6. **全チャンクの処理が終わったら、モデルを明示的に解放する（必須）:**
   ```bash
   bash ~/.claude/scripts/ollama-run.sh --unload "$OLLAMA_MODEL"
   ```
   ステップ 2 の各呼び出しは `OLLAMA_KEEP_ALIVE=5m` を付けてモデルを保持する。
   保持しないとチャンクごとにモデルのロードが発生し、実測で cold 41s / warm 4s の差が
   チャンク数だけ積み上がる。その代わり、**ループを抜けた時点で解放しなければ
   モデルが VRAM を占有し続ける**。
   途中でレビューを中止する場合も、中止を報告する前にこの解放を実行する。

   > **この項目は Ollama パスを実行した場合にのみ行う。**
   > ステップ 2 で Haiku パス（フォールバック、および CASPER のように Ollama を使わない設定）に
   > 入った場合は**実行しない**。CASPER には `$OLLAMA_MODEL` が定義されておらず、
   > 空の値で `--unload` を呼ぶと usage エラーになる。ロード済みのモデルも存在しない。

   > **`--unload` は失敗しても終了コード 0 を返す。**
   > 未ロードのモデルや存在しないモデル名でも正常終了する契約のため（`/api/generate` は
   > 未知のモデルに 404 を返す）、終了コードで解放の成否は判定できない。
   > 失敗時は stderr に `Warning: unload request failed for model: <名前>` が出るので、
   > **警告が出たときは `$(ollama_base_url)/api/ps` で常駐状況を確認する**。
   > 確認しない場合でも `5m` の自己失効が残るが、それまで VRAM は占有されたままになる。

> ⚠ **解放を `trap` で自動化しようとしないこと。**
> このチャンクループはシェルのループではなく、1チャンクにつき Bash 呼び出しが 1 回の
> **エージェント駆動のループ**である。ある呼び出しで張った `trap` はその呼び出しの終了時に発火し、
> 次のチャンクには残らない（環境変数も同様に持続しない）。
> したがって解放の担保は次の三層で行う:
> 1. **呼び出し単位のシグナル**（INT / TERM）は `ollama-run.sh` 自身が処理する。
>    `keep_alive` の値に関わらず必ず unload される
> 2. **ループ終了後の明示 unload**（上記の項目 6、およびステップ 2 の失敗分岐）
> 3. **`5m` の自己失効**。1・2 の両方が飛んだ場合（セッションごと落ちた等）でも
>    5分で自動的に解放される。無期限保持にしてはならないのはこのため

---

## ステップ 2: Ollama 可否チェックと起動

```bash
_magi_base_url=$(bash -c 'source ~/.claude/hooks/lib/ollama.sh && ollama_base_url' 2>/dev/null)
curl -sf --max-time 5 "${_magi_base_url:-http://localhost:11434}/api/tags" 2>/dev/null \
  | jq -r '.models[].name' 2>/dev/null | grep -qxF "$OLLAMA_MODEL"
```

### Ollama が使える場合

1. Read ツールで以下を読み込む（repo 内を優先、なければ絶対パスで `~/.claude/` を使用）:
   - `skills/magi-common/references/task-base.md`（repo 内）または `/home/<user>/.claude/skills/magi-common/references/task-base.md`
   - `skills/<persona>/references/task-instruction.md`（repo 内）または `/home/<user>/.claude/skills/<persona>/references/task-instruction.md`
   - `skills/<persona>/references/review-criteria.md`（repo 内）または `/home/<user>/.claude/skills/<persona>/references/review-criteria.md`
   - `$OUTPUT_FORMAT_PATH`（省略時は `skills/magi-common/references/output-format.md`）（repo 内）または `/home/<user>/.claude/` 配下の同パス

2. system/prompt を分離して一時ファイルに書き出す（差分内の特殊文字によるシェル誤展開を防ぐため）:

   まず一時ディレクトリを作成する（並列実行時のファイル名競合を防ぐため）:
   ```bash
   MAGI_TMPDIR=$(mktemp -d)
   ```

   **$MAGI_TMPDIR/system.txt（背景知識・ロール定義）:**
   ```
   [task-instruction.md の内容をそのまま展開]
   [review-criteria.md の内容をそのまま展開]
   ```
   **CASPER のみ:** system.txt に `$OUTPUT_FORMAT_PATH` の内容より前に以下を追加:
   ```
   ---CLAUDE.md---
   [CLAUDE_RULES の内容]
   ```
   **$MAGI_TMPDIR/system.txt（出力契約）:**
   ```
   [$OUTPUT_FORMAT_PATH の内容をそのまま展開]
   ```
   **BALTHASAR のみ:** $MAGI_IMPACT_CONTEXT が設定されている場合、system.txt の末尾に以下を追加:
   ```
   ---IMPACT_CONTEXT---
   [$MAGI_IMPACT_CONTEXT の内容]
   ```
   **LELIEL のみ:** $MAGI_IMPACT_CONTEXT が設定されている場合、system.txt の末尾（読み込んだ出力契約ファイル `$OUTPUT_FORMAT_PATH` の内容の後）に以下を追加:
   ```
   <IMPACT_CONTEXT> に列挙されている呼び出し元を1件ずつ順に検査すること。各呼び出し元について、
   渡している引数が新しいシグネチャと一致するかを個別に確認してから結論を書くこと。
   一致しない箇所だけを finding として報告すること。
   ```

   **$MAGI_TMPDIR/prompt.txt（実タスク）:**
   ```
   [task-base.md の内容をそのまま展開]

   <TASK>
   [$CHUNK_DIFF の内容]
   </TASK>
   ```
   **LELIEL のみ:** $MAGI_IMPACT_CONTEXT が設定されている場合、prompt.txt の <TASK> タグの前に以下を追加:
   ```
   <IMPACT_CONTEXT>
   [$MAGI_IMPACT_CONTEXT の内容]
   </IMPACT_CONTEXT>
   ```

3. 一時ファイルを Ollama に渡す:
   ```bash
   OLLAMA_KEEP_ALIVE=5m bash ~/.claude/scripts/ollama-run.sh "$OLLAMA_MODEL" "$MAGI_TMPDIR/system.txt" < "$MAGI_TMPDIR/prompt.txt" || {
     echo "⚠ Ollama 排他ロック取得失敗。ollama プロセスを確認してください。"
     rm -rf "$MAGI_TMPDIR"
     bash ~/.claude/scripts/ollama-run.sh --unload "$OLLAMA_MODEL"
     exit 1
   }
   rm -rf "$MAGI_TMPDIR"
   ```
   `OLLAMA_KEEP_ALIVE=5m` は次のチャンクでモデルを再ロードしないための保持指定。
   `$MAGI_TMPDIR` の作成と削除は**チャンク単位**のまま変更しない（モデルの解放とは責務が別）。

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
- `$OUTPUT_FORMAT_PATH`（省略時は `skills/magi-common/references/output-format.md`）

取得したコード・差分とペルソナ定義・references/ の内容を合わせて `Agent(subagent_type="general-purpose", model="haiku")` に渡す:
- `agents/<persona>.md` の全内容（ペルソナ・人格）
- `skills/magi-common/references/task-base.md` の内容（共通タスク指示）
- `skills/<persona>/references/task-instruction.md` の内容（ロール定義・few-shot例）
- `skills/<persona>/references/review-criteria.md` の内容（レビュー観点・重大度基準）
- `$OUTPUT_FORMAT_PATH` の内容（出力形式）
- 「上記の $PERSONA_NAME ペルソナに従い、担当観点でレビューしてください」という指示

**CASPER のみ:** エージェントへの指示に以下を追加:
> CLAUDE.md 群の読み込みは agents/casper.md のステップ 1 で CASPER 自身が行う（`~/.claude/CLAUDE.md`、`./CLAUDE.md`、`./CLAUDE.local.md`）。

**BALTHASAR のみ:** $MAGI_IMPACT_CONTEXT が設定されている場合、エージェントへの指示に以下を追加:
> システムコンテキストとして以下の呼び出し元情報を参照してください: [MAGI_IMPACT_CONTEXT]

**LELIEL のみ:** $MAGI_IMPACT_CONTEXT が設定されている場合、エージェントへの指示に以下を追加:
> 以下の <IMPACT_CONTEXT> タグ内の呼び出し元スニペットをレビューの根拠として使用してください: [MAGI_IMPACT_CONTEXT]

---

## ステップ 2.5: Normalizer（v2契約・単体実行時のみ）

**`$OUTPUT_FORMAT_PATH` が `output-format-v2.md` を指しており、かつ `$MAGI_ORCHESTRATED` が `true` でない場合にのみ実行する。** それ以外（v1ペルソナ、またはオーケストレーターから呼ばれた場合）はこのステップをスキップし、ステップ3にそのまま進む。

1. `$MAGI_TMPDIR=$(mktemp -d)` で作業ディレクトリを作成する。
2. 全チャンクの生結果（`$RESULT`）を、`=== PERSONA: $PERSONA_NAME / CHUNK: <path> (<n>) ===` ヘッダーを保ったまま `$NORMALIZE_INPUT` として保持する。
3. `skills/magi-common/references/normalizer.md`（repo 内）または `~/.claude/skills/magi-common/references/normalizer.md` を Read ツールで読み込み、記載の手順に従ってNormalizerを実行する。
4. 成功した場合、`$MAGI_TMPDIR/normalizer.json` の内容を `$NORMALIZED_RESULT` として保持する。人間可読な箇条書き（`- path:line — headline`）も添えて最終結果とする。**severityが付かないことを出力冒頭に明記する**（例: 「※ この結果はDETECTION NOTES契約（v2）のためseverity（重大度）は付与されません」）。
5. 失敗（`NORMALIZE_SKIPPED`/`NORMALIZE_ERROR`）した場合は、`normalizer.md`の契約に従いHaiku fallbackへ切り替えるか、正規化前の生結果をその旨明記の上で表示する。
6. `$MAGI_TMPDIR` を削除する。

単体実行では監査・重要度判定は行わない（PR全体の文脈が要るため、1ペルソナ単体の結果だけでは意味を成さない）。

---

## ステップ 3: 結果の表示

$PERSONA_NAME のレビュー結果（ステップ2.5を実行した場合はその結果）をそのまま表示する。
どちらのパスを使ったか（Ollama / Haiku fallback）を冒頭に 1 行記載する。
ローカルLLMが英語で出力した場合でも、Claude が日本語に翻訳してユーザーに提示する。
