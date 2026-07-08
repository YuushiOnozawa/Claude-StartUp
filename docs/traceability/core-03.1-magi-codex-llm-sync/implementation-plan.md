# Implementation Plan: Core 03.1 — MAGI / Codex / ローカルLLM連携の実体・参照・割当ズレ

> ステータス: approved（2026-07-08 人間承認済み）
> 対応 specification: approved（2026-07-07）

## 前提確認

| 項目 | 現状 |
|---|---|
| `agents/leliel.md` | 存在する（削除対象） |
| 6ペルソナ SKILL.md の `エージェント定義` 行 | 全件残存（削除対象） |
| `execution-steps.md` の `$AGENT_PATH` 参照 | L8・L112-130 に残存（除去対象） |
| スクリプト相対パス参照（5箇所） | 残存（絶対パスへ修正対象） |
| `setup/800-ollama-models.sh` | 存在する（`setup.sh` から未参照。削除対象） |
| `setup/850-codex.sh` | 存在する（変更なし。core-03.3 に委任） |

---

## 実装項目一覧

| IMPL ID | 内容 | 対応 SPEC | 変更ファイル | 実行方法 |
|---|---|---|---|---|
| IMPL-03.1-01 | 6ペルソナ SKILL.md から `エージェント定義` 行を削除 | SPEC-03.1-01 | `skills/{balthasar,casper,leliel,melchior,metatron,sandalphon}/SKILL.md` | `/dev-flow` |
| IMPL-03.1-02 | `agents/leliel.md` を `git rm` | SPEC-03.1-02 | `agents/leliel.md` | `/dev-flow`（PR-A で IMPL-03.1-01 と同時） |
| IMPL-03.1-03 | `execution-steps.md` の `$AGENT_PATH`・`agents/` 参照除去・Haiku fallback 更新 | SPEC-03.1-03 | `skills/magi-common/references/execution-steps.md` | `/dev-flow` |
| IMPL-03.1-04 | スクリプト相対パスを絶対パスに修正（5箇所） | SPEC-03.1-04 | `skills/magi-common/references/execution-steps.md`・`skills/magi-fast/SKILL.md`・`skills/magi-hard/SKILL.md` | `/dev-flow`（PR-B2。PR-B1 とは別 PR） |
| IMPL-03.1-05 | `setup/800-ollama-models.sh` を `git rm`・`setup/401-ollama.sh` のコメント削除 | SPEC-03.1-05 | `setup/800-ollama-models.sh`・`setup/401-ollama.sh` | `/codegen` + `/commit` |
| IMPL-03.1-06 | `OLLAMA_MODEL`・`PERSONA_NAME` 行が残っていることの確認（非変更検証） | SPEC-03.1-06 | なし（変更なし） | PR-A 検証で確認 |
| IMPL-03.1-07 | `setup/850-codex.sh` が変更されていないことの確認（非変更検証） | SPEC-03.1-07 | なし（変更なし） | PR-C 検証で確認 |

---

## PR 分割

### PR-A: ペルソナ SKILL.md 整理 + leliel.md 削除（IMPL-03.1-01, IMPL-03.1-02）

**作業内容**:
- 6ペルソナ SKILL.md（balthasar/casper/leliel/melchior/metatron/sandalphon）の「ペルソナ固有設定」テーブルから `エージェント定義` 行を削除する
- `agents/leliel.md` を `git rm` する

**実行方法**: `/dev-flow`（6ファイル + `git rm` 操作があるため）

**依存関係**: なし（先頭 PR）

**検証**:
```bash
# agents/ 参照が残っていないこと
grep -rn "agents/" \
  skills/balthasar/SKILL.md skills/casper/SKILL.md skills/leliel/SKILL.md \
  skills/melchior/SKILL.md skills/metatron/SKILL.md skills/sandalphon/SKILL.md
# → 0 matches

# OLLAMA_MODEL・PERSONA_NAME 行が残っていること（IMPL-03.1-06）
grep -c "OLLAMA_MODEL" skills/balthasar/SKILL.md skills/casper/SKILL.md \
  skills/leliel/SKILL.md skills/melchior/SKILL.md skills/metatron/SKILL.md skills/sandalphon/SKILL.md
# → 各ファイル 1 match

# agents/leliel.md が存在しないこと
ls agents/leliel.md 2>&1 | grep "No such file"

# agents/code-reviewer.md が残っていること
ls agents/code-reviewer.md
```

> **注意**: `leliel/SKILL.md` は SPEC-03.1-01/02 の両要件に関わるため、同一 PR で変更する（SPEC-03.1-02 境界条件）

---

### PR-B1: execution-steps.md の agents/ 参照除去・Haiku fallback 更新（IMPL-03.1-03）

> **着手前ブロッカー（必須確認）:**
> - `execution-steps.md` で Haiku fallback の Agent() に渡している参照ファイルを確認し、SPEC-03.1-03 が要求する4ファイル（`task-base.md`・`task-instruction.md`・`review-criteria.md`・`output-format.md`）と一致させる。**確認コマンド: `grep -n "task-\|output-format\|review-criteria" skills/magi-common/references/execution-steps.md`**
> - `$CLAUDE_RULES` の取得がステップ 1 に存在することを確認する。**確認コマンド: `grep -n "CLAUDE_RULES" skills/magi-common/references/execution-steps.md`**
> - 上記 2 点が未確認の場合、PR-B1 に着手しない

**作業内容**:
- `execution-steps.md` から以下を削除・更新:
  - L8: `$AGENT_PATH` 変数行削除
  - L112-116: agents/ 前提条件段落・エージェント定義読み込みブロック削除
  - L115-130: Agent() 引数リストから `agents/<persona>.md の全内容` 行削除
  - L133: CASPER 固有の `agents/casper.md` 参照行を `$CLAUDE_RULES` 渡しに置き換え
  - Haiku fallback の Agent() 引数を `task-base.md`・`task-instruction.md`・`review-criteria.md`・`output-format.md` のみに更新

**実行方法**: `/dev-flow`（`execution-steps.md` は MAGI の中枢ファイル。CI + magi-hard レビューを経ること）

**依存関係**: PR-A が merge 済みであること
- 根拠: `execution-steps.md` の Haiku fallback が `agents/leliel.md`（L133 近傍の CASPER 固有 agents/ 参照）を前提として記述されており、PR-A での `leliel.md` 削除後でなければ整合が取れない。また PR-A で `leliel/SKILL.md` の agents/ 参照が削除されているため、PR-B1 の除去後も SKILL → agents の参照循環が発生しない。

**検証**:
```bash
# agents/ 参照がないこと
grep -n "agents/" skills/magi-common/references/execution-steps.md
# → 0 matches

# $AGENT_PATH がないこと
grep -n "AGENT_PATH" skills/magi-common/references/execution-steps.md
# → 0 matches

# Haiku fallback に task-instruction.md が含まれること
grep -n "task-instruction" skills/magi-common/references/execution-steps.md
# → 1 match 以上

# CASPER ブロックに $CLAUDE_RULES が渡されること
grep -n "CLAUDE_RULES" skills/magi-common/references/execution-steps.md
# → 1 match 以上（ステップ1取得 + Haiku Agent 引数渡し）
```

---

### PR-B2: スクリプト相対パスを絶対パスに修正（IMPL-03.1-04）

**作業内容**:
- スクリプト相対パスを絶対パスに修正（5箇所）:
  - `execution-steps.md` L26: `bash scripts/magi-diff-filter.sh` → `bash "$HOME/.claude/scripts/magi-diff-filter.sh"`
  - `execution-steps.md` L31: `bash scripts/magi-split-hunk.sh 400` → `bash "$HOME/.claude/scripts/magi-split-hunk.sh" 400`
  - `skills/magi-fast/SKILL.md` L36: `bash scripts/magi-diff-filter.sh` → `bash "$HOME/.claude/scripts/magi-diff-filter.sh"`
  - `skills/magi-hard/SKILL.md` L34: `bash scripts/magi-diff-filter.sh` → `bash "$HOME/.claude/scripts/magi-diff-filter.sh"`
  - `skills/magi-hard/SKILL.md` L42: `bash scripts/magi-impact-context.sh` → `bash "$HOME/.claude/scripts/magi-impact-context.sh"`

**実行方法**: `/dev-flow`（magi-fast/hard の中枢ファイルを変更するため）

**依存関係**: PR-B1 が merge 済みであることを推奨（同一ファイル `execution-steps.md` への変更のため、コンフリクトを避けるため順序付け）

**検証**:
```bash
# bash scripts/ 相対パスがないこと
grep -rn "bash scripts/" \
  skills/magi-fast/SKILL.md skills/magi-hard/SKILL.md \
  skills/magi-common/references/execution-steps.md
# → 0 matches

# $HOME/.claude/scripts/ 形式になっていること
grep -rn 'bash "\$HOME/.claude/scripts/' \
  skills/magi-fast/SKILL.md skills/magi-hard/SKILL.md \
  skills/magi-common/references/execution-steps.md
# → 5 matches
```

手動検証（SPEC-03.1-04）:
- 別プロジェクト cwd からスキル実行し、スクリプトが見つかること
- 成功条件: diff 出力または「差分なし」が返る（スクリプト not found エラーが出ない）
- 失敗条件: `bash: /home/.claude/scripts/....: No such file or directory`

---

### PR-C: setup/800-ollama-models.sh 削除（IMPL-03.1-05, IMPL-03.1-07）

**作業内容**:
- `setup/800-ollama-models.sh` を `git rm`
- `setup/401-ollama.sh` L3 のコメント `モデルのダウンロードは 800-ollama-models.sh で行う` を削除

**実行方法**: `/codegen` + `/commit`（シンプルな削除・コメント除去のため）

**依存関係**: なし（PR-A/B1/B2 と独立して並行可）

**検証**:
```bash
# 削除前: setup.sh から参照がないことを確認（blocker）
grep "800\|ollama-models" setup/setup.sh
# → 0 matches（確認済みだが念のため確認してから git rm）

# 削除後
ls setup/800-ollama-models.sh 2>&1 | grep "No such file"
grep "800-ollama-models" setup/401-ollama.sh
# → 0 matches

# 850-codex.sh が変更されていないこと（IMPL-03.1-07）
git diff setup/850-codex.sh
# → 差分なし
```

---

## 依存関係グラフ

```
PR-A（ペルソナ SKILL.md 整理 + leliel.md 削除）
  └→ PR-B1（execution-steps.md agents/ 参照除去・Haiku fallback 更新）
       └→ PR-B2（スクリプト相対パスを絶対パスに修正）

PR-C（800-ollama-models.sh 削除）  ← 独立（PR-A/B1/B2 と並行可）
```

---

## 実装前に決めるべきこと

| # | 事項 | 現状 | blocker |
|---|---|---|---|
| 1 | **Haiku fallback 入力ファイルの確定**（PR-B1 着手前） | SPEC-03.1-03 準拠: `task-base.md`・`task-instruction.md`・`review-criteria.md`・`output-format.md`。PR-B1 着手前に `execution-steps.md` の現行 Haiku パスと突合して確認する | **PR-B1 blocker** |
| 2 | **`$CLAUDE_RULES` 取得タイミングの確認**（PR-B1 着手前） | ステップ 1 で既に取得済みであることを `grep -n "CLAUDE_RULES" execution-steps.md` で確認する | **PR-B1 blocker** |
| 3 | `setup/401-ollama.sh` の削除対象行の特定（PR-C 着手前） | `grep -n "800-ollama-models" setup/401-ollama.sh` で行番号を確認する | PR-C blocker |

---

## 実働環境への手動操作（PR 外）

| 操作 | タイミング | 手順 |
|---|---|---|
| `~/.claude/agents/leliel.md` の削除 | PR-A merge 後・core-02 還流フローで対応 | 下記参照 |

### 手順と安全対策

```bash
# 1. バックアップ（削除前）
cp ~/.claude/agents/leliel.md ~/.claude/agents/leliel.md.bak.$(date +%Y%m%d)

# 2. 共存期間リスクの確認
#    PR-A merge 後・手動削除前の間、新 SKILL.md（agents/ 参照なし）と
#    旧 live leliel.md が共存する。
#    Agent(subagent_type="leliel") の直接呼び出しはスキルフローをバイパスするため
#    この期間は意図せずレガシー leliel.md が使われる可能性がある。
#    → 共存期間を最小化するため、PR-A merge 後できるだけ早く手動削除を実施する。

# 3. /sync-check で確認してから削除
/sync-check  # → agents/leliel.md が「削除予定（既知）」に出ること

# 4. 削除
rm ~/.claude/agents/leliel.md

# 5. 事後確認
ls ~/.claude/agents/leliel.md 2>&1 | grep "No such file"

# 6. 復元手順（誤削除時）
cp ~/.claude/agents/leliel.md.bak.$(date +%Y%m%d) ~/.claude/agents/leliel.md
```

---

## 注意

- `execution-steps.md` は全ペルソナ共有の中枢ファイル。PR-B1 は必ず `/dev-flow`（magi-hard レビュー通過）で進める
- PR-A で `leliel/SKILL.md` と `agents/leliel.md` を同時に変更することで「SKILL.md が削除済みファイルを参照する中間状態」を作らない（SPEC-03.1-02 境界条件）
- `~/.claude/settings.json` の hooks は一切変更しない
