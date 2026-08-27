---
name: casper
desc: MAGI CASPER（CLAUDE.md準拠・ルール遵守観点）でコードをレビューする。Trigger: "/casper", "ルール遵守チェック", "CASPERでレビュー", "CLAUDE.md準拠チェック"
argument-hint: "<ファイルパス または差分>"
---
# CASPER スキル

MAGI CASPER（ルールの番人）の観点でコードをレビューする。
CLAUDE.md 準拠チェックは Claude 自身が判定するほうが精度が高いため、Claude Haiku を使用する。

## ペルソナ固有設定

| 項目 | 値 |
|-----|---|
| PERSONA_NAME | `CASPER` |
| エージェント | Claude Haiku（`Agent(subagent_type="general-purpose", model="haiku")`） |
| `AGENT_PATH` | 解決した `$ROOT/skills/casper/SKILL.md` と `$ROOT/skills/casper/references/` をペルソナ定義として使う |
| CLAUDE_RULES | `~/.claude/CLAUDE.md`、`./CLAUDE.md`、`./CLAUDE.local.md` を読み込む |
| OUTPUT_FORMAT_PATH | `skills/magi-common/references/output-format-v2.md` |

## 参照ファイル

- `skills/magi-common/references/execution-steps.md` — 共通実行手順（Read して展開する）
- `skills/magi-common/references/output-format-v2.md` — 共通出力フォーマット（DETECTION NOTES契約、v2）
- `references/task-instruction.md` — ロール定義・few-shot出力例
- `references/review-criteria.md` — レビュー観点・重大度基準・守備範囲外

## 実行

実行前にリポジトリのルートを解決し、次の順序で存在するファイルを Read して
`$CLAUDE_RULES` として保持する。存在しないファイルは無視する。

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
AGENT_PATH="$ROOT/skills/casper/SKILL.md"
AGENT_REFERENCES_PATH="$ROOT/skills/casper/references"
```

1. `~/.claude/CLAUDE.md`
2. `$ROOT/CLAUDE.md`（`./CLAUDE.md`）
3. `$ROOT/CLAUDE.local.md`（`./CLAUDE.local.md`）

読み込んだ `$CLAUDE_RULES` は、CASPER の system/prompt に `---CLAUDE.md---` 区切りで追加し、
レビュー対象 diff とともに Haiku へ渡す。これが CASPER における CLAUDE.md 読み込みの唯一の経路である。

`skills/magi-common/references/execution-steps.md` のステップ 2 で、task-instruction、review-criteria、
`$OUTPUT_FORMAT_PATH` を `$MAGI_TMPDIR/system.txt` に組み立て終えた直後、Haiku を呼び出す前に、次の
追記を行う。追記後の `$MAGI_TMPDIR/system.txt` を Haiku の system content として渡す。

```bash
if [ -n "$CLAUDE_RULES" ]; then
  {
    printf '%s\n' '---CLAUDE.md---'
    printf '%s\n' "$CLAUDE_RULES"
  } >> "$MAGI_TMPDIR/system.txt"
fi
```

`skills/magi-common/references/execution-steps.md` を Read し、「ペルソナ固有設定」の値を当てはめて
手順を実行する。`$AGENT_PATH` はこの SKILL.md を使い、repo 内の別エージェント定義ファイルは使わない。
オーケストレーターから呼ばれた場合は `MAGI_ORCHESTRATED=true` を受け取り、
Normalizer は `skills/flow-common/references/casper-engine.md` の共通契約に従う呼び出し元へ委ねる。

**CASPER は Ollama パスを使用しない。**
execution-steps.md のステップ 2 で Ollama チェックをスキップし、
直接「Ollama が使えない場合（Haiku パス）」を実行する。
Haiku は標準モデルとして指定済みのため、`AskUserQuestion` によるフォールバック確認は不要である。
