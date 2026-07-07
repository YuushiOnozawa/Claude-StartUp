# Specification: Core 03.1 — MAGI / Codex / ローカルLLM連携の実体・参照・割当ズレ

> ステータス: approved（2026-07-07 人間確認済み）
> 対応 requirements: approved（2026-07-07）

## 現状確認（2026-07-07）

| 項目 | 現状 |
|---|---|
| `agents/leliel.md` | 存在する（削除対象） |
| `agents/code-reviewer.md` | 存在する（本 core の対象外） |
| 6ペルソナ SKILL.md の `エージェント定義` 行 | 全件残存（balthasar/casper/leliel/melchior/metatron/sandalphon） |
| `execution-steps.md` の `$AGENT_PATH` 参照 | L8、L112-130 に残存 |
| スクリプト相対パス参照 | execution-steps.md L26,31 / magi-fast/SKILL.md L36 / magi-hard/SKILL.md L34,42 |
| `setup/800-ollama-models.sh` | 存在するが `setup.sh` から未参照（事実上無効化済み） |
| `setup/850-codex.sh` | 存在する（導入確認のみ。変更不要） |

---

## SPEC-03.1-01: 全ペルソナ SKILL.md から `エージェント定義` 行を削除する

> REQ-03.1-01 対応

### 振る舞い

| 項目 | 内容 |
|---|---|
| 対象ファイル | `skills/balthasar/SKILL.md`・`skills/casper/SKILL.md`・`skills/leliel/SKILL.md`・`skills/melchior/SKILL.md`・`skills/metatron/SKILL.md`・`skills/sandalphon/SKILL.md` |
| 操作 | 各ファイルの「ペルソナ固有設定」テーブルから `エージェント定義` 行を削除する |
| 変更対象行の形式 | `\| エージェント定義 \| \`agents/<persona>.md\`（repo 内）または \`/home/<user>/.claude/agents/<persona>.md\` \|` |
| 保持する行 | `OLLAMA_MODEL`・`PERSONA_NAME` 行は変更しない |

### 事後条件

- 6ファイル全てに `agents/` の文字列が含まれない
- 「ペルソナ固有設定」テーブルは 2 行（`OLLAMA_MODEL`・`PERSONA_NAME`）のみになる

### fail / warn / info

| 状態 | 判定 |
|---|---|
| 削除後も `agents/` の記述が残っている | fail |
| `OLLAMA_MODEL`・`PERSONA_NAME` 行が消えた | fail |

### 境界条件

- `leliel/SKILL.md` は SPEC-03.1-02（agents/leliel.md 削除）と同時に変更することで整合を保つ
- `skills/magi-fast/SKILL.md`・`skills/magi-hard/SKILL.md` はペルソナ SKILL.md ではないため対象外

---

## SPEC-03.1-02: `agents/leliel.md` を削除する

> REQ-03.1-02 対応

### 振る舞い

| 項目 | 内容 |
|---|---|
| 操作 | `git rm agents/leliel.md` |
| 事前条件 | `agents/leliel.md` が存在する |
| 事後条件 | `agents/leliel.md` が repo 上に存在しない（実働環境側の削除は core-02 還流フローで対応） |
| 他ファイルへの影響 | `agents/code-reviewer.md` は変更しない（本 core の対象外） |

### fail / warn / info

| 状態 | 判定 |
|---|---|
| 削除後に `agents/leliel.md` が存在する | fail |
| `agents/code-reviewer.md` が消えた | fail（対象外ファイルを誤削除） |

### 境界条件

- SPEC-03.1-01 と同一 PR で実施する（SKILL.md の参照行削除と同時にファイルを消すことで、参照先不在の中間状態を作らない）
- 実働環境（`~/.claude/agents/leliel.md`）の削除は core-02 還流フローで対応（本 core の実装 PR には含まない）

---

## SPEC-03.1-03: `execution-steps.md` から agents/ 参照を除去し、Haiku fallback を agents/ 非依存に更新する

> REQ-03.1-03 対応

### 振る舞い

**削除する記述:**

| 場所 | 削除内容 |
|---|---|
| L8（変数リスト） | `- $AGENT_PATH — Haiku fallback 時のエージェント定義パス（例: agents/melchior.md）` の行 |
| L112（前提条件） | `前提条件: setup.sh で agents/ が ~/.claude/agents/ にコピー済みであること。` の段落 |
| L113-116（エージェント定義読み込み） | `エージェント定義の読み込み（以下の順で試みる）:` から `2. /home/<user>/.claude/agents/<persona>.md` までの段落 |
| L115-130（Agent 呼び出し引数） | `agents/<persona>.md の全内容（ペルソナ・人格）` の行（Agent() 引数リストから削除） |
| L133（CASPER 固有ブロック） | `CLAUDE.md 群の読み込みは agents/casper.md のステップ 1 で CASPER 自身が行う（...）` の行 |

**更新する記述（Haiku fallback の Agent() 呼び出し）:**

Haiku fallback では `agents/<persona>.md` を使わず、Ollama パスと同じ references/ ファイル群のみを使う:
- `task-base.md`（共通タスク指示）
- `task-instruction.md`（ロール定義・ペルソナ定義・few-shot 例）
- `review-criteria.md`（レビュー観点・重大度基準）
- `output-format.md`（出力形式）

**CASPER 固有の追加（L133 の置き換え）:**

> CASPER のみ: Haiku Agent への指示に `$CLAUDE_RULES` の内容を追加する（`~/.claude/CLAUDE.md`、`./CLAUDE.md`、`./CLAUDE.local.md` を結合したもの。ステップ 1 で取得済み）

これにより `agents/casper.md` のステップ 1 に依存していた CLAUDE.md 読み込み責務を、execution-steps.md のステップ 1 に移管する（ステップ 1 では既に CASPER のみのブロックで `$CLAUDE_RULES` を取得している）。

### 事後条件

- `execution-steps.md` に `$AGENT_PATH`・`agents/` の文字列が含まれない（L133 の CASPER 固有行を含む）
- Haiku fallback の Agent() 呼び出しが `agents/` 読み込みなしで完結する
- CASPER の Haiku fallback では `$CLAUDE_RULES` が Agent() へ渡される
- Ollama パスと Haiku fallback パスで参照するファイル群が一致している

### fail / warn / info

| 状態 | 判定 |
|---|---|
| 更新後に `$AGENT_PATH` が残っている | fail |
| 更新後に `agents/` 文字列が残っている | fail |
| Haiku fallback の Agent() 呼び出しに task-instruction.md が含まれていない | fail |

### 境界条件

- `CASPER のみ`・`BALTHASAR のみ`・`LELIEL のみ` の条件ブロックは各該当行のみ変更する。他ペルソナの条件ブロックは触れない
- Haiku fallback は `Agent(subagent_type="general-purpose", model="haiku")` を引き続き使う（呼び出し方式は変更しない）

---

## SPEC-03.1-04: スクリプト参照を相対パスから絶対パスに修正する

> REQ-03.1-04 対応

### 振る舞い

**変換ルール**: `bash scripts/<name>.sh` → `bash "$HOME/.claude/scripts/<name>.sh"`

**対象箇所:**

| ファイル | 変更前 | 変更後 |
|---|---|---|
| `skills/magi-common/references/execution-steps.md` L26 | `bash scripts/magi-diff-filter.sh` | `bash "$HOME/.claude/scripts/magi-diff-filter.sh"` |
| `skills/magi-common/references/execution-steps.md` L31 | `bash scripts/magi-split-hunk.sh 400` | `bash "$HOME/.claude/scripts/magi-split-hunk.sh" 400` |
| `skills/magi-fast/SKILL.md` L36 | `bash scripts/magi-diff-filter.sh` | `bash "$HOME/.claude/scripts/magi-diff-filter.sh"` |
| `skills/magi-hard/SKILL.md` L34 | `bash scripts/magi-diff-filter.sh` | `bash "$HOME/.claude/scripts/magi-diff-filter.sh"` |
| `skills/magi-hard/SKILL.md` L42 | `bash scripts/magi-impact-context.sh` | `bash "$HOME/.claude/scripts/magi-impact-context.sh"` |

**変更しないもの:**

- `execution-steps.md` L97: `bash ~/.claude/scripts/ollama-run.sh`（既に絶対パス）

### 事後条件

- 対象5箇所全てが `"$HOME/.claude/scripts/..."` 形式になっている
- 他プロジェクト cwdで MAGI スキルを実行しても、スクリプトが見つかる

### 検証方法

```bash
# 変更後の確認（"bash scripts/" が残っていないこと）
grep -rn "bash scripts/" skills/magi-fast/SKILL.md skills/magi-hard/SKILL.md \
  skills/magi-common/references/execution-steps.md
# → 0 matches であること

# 手動検証: 別プロジェクトcwdからスキル実行
cd ~/srcs/other-project && /magi-fast  # 「差分なし」ではなく正常動作すること
```

### fail / warn / info

| 状態 | 判定 |
|---|---|
| 対象ファイルに `bash scripts/` が残っている | fail |
| `$HOME` の展開が省略されて絶対パスになっていない | fail |

---

## SPEC-03.1-05: `setup/800-ollama-models.sh` を削除する

> REQ-03.1-05 対応

### 振る舞い

| 項目 | 内容 |
|---|---|
| 操作1 | `git rm setup/800-ollama-models.sh` |
| 操作2 | `setup/401-ollama.sh` L3 のコメント `モデルのダウンロードは 800-ollama-models.sh で行う` を削除する |
| 前提確認 | `setup.sh` が `800-ollama-models.sh` を参照していないこと（確認済み: 0 matches） |
| 事後条件 | `setup/800-ollama-models.sh` が存在しない / `setup/401-ollama.sh` に `800-ollama-models.sh` の文字列が含まれない |

### fail / warn / info

| 状態 | 判定 |
|---|---|
| 削除後も `setup/800-ollama-models.sh` が存在する | fail |
| `setup.sh` から `800-ollama-models.sh` の参照が残っている | fail（削除前に参照を除去する） |
| `setup/401-ollama.sh` に `800-ollama-models.sh` への言及が残っている | fail（古いコメントが誤誘導） |

### 境界条件

- `setup.sh` から既に未参照であることを実装前に再確認する（`grep "800\|ollama-models" setup.sh`）
- 他の setup スクリプト（特に `401-ollama.sh`）からの参照・コメントも削除対象とする

---

## SPEC-03.1-06: SKILL.md の OLLAMA_MODEL 記載は維持する（追加実装なし）

> REQ-03.1-06 対応

- `OLLAMA_MODEL` 行は各 SKILL.md で現状値を維持する（「WindowsホストOllamaに必要なモデル」の文書として機能）
- LELIEL: `deepseek-r1:8b`、METATRON: `devstral:latest`、他は現状のまま

### 境界条件

- SPEC-03.1-01 の `エージェント定義` 行削除時に `OLLAMA_MODEL` 行を誤削除しないこと

---

## SPEC-03.1-07: `setup/850-codex.sh` の「導入確認のみ」を維持する（追加実装なし）

> REQ-03.1-07 対応

- `setup/850-codex.sh` は現状維持（core-03.3 で自動インストールに変更する予定）
- README への Codex CLI 動作確認済みバージョン記載は **core-03.3 の実装 PR** に委ねる

### 境界条件

- 本 core では `setup/850-codex.sh` を変更しない

---

## 自動化対象と手動確認対象

| 操作 | 区分 | 備考 |
|---|---|---|
| 6 SKILL.md の `エージェント定義` 行削除 | 自動（実装 PR） | SPEC-03.1-01 |
| `agents/leliel.md` の削除 | 自動（実装 PR、`git rm`） | SPEC-03.1-02 |
| `execution-steps.md` の agents/ 参照除去 | 自動（実装 PR） | SPEC-03.1-03 |
| スクリプト相対パスの絶対パス修正（5箇所） | 自動（実装 PR） | SPEC-03.1-04 |
| `setup/800-ollama-models.sh` 削除 + `401-ollama.sh` コメント削除 | 自動（実装 PR） | SPEC-03.1-05 |
| 実働環境の `~/.claude/agents/leliel.md` 削除 | 手動（core-02 還流フローで対応） | SPEC-03.1-02 境界条件 |
| 別 cwd での MAGI スキル動作確認 | 手動 | SPEC-03.1-04 検証 |

---

## 未確定事項

なし（全件 2026-07-07 確定）

---

## 確定した仕様上の決定（2026-07-07）

| # | 事項 | 決定 |
|---|---|---|
| 1 | agents/ 参照の整理方針 | 全削除（PR #203 完遂）。復元しない |
| 2 | Haiku fallback のペルソナ定義 | agents/<persona>.md なし。task-instruction.md で代替 |
| 3 | METATRON devstral | 継続。代替は別 Issue |
| 4 | Codex CLI バージョン固定 | 固定しない。README 記載のみ（core-03.3 担当） |
| 5 | setup/800-ollama-models.sh | 削除（setup.sh から既に未参照） |
