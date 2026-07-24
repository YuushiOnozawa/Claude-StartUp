---
name: magi-fast
description: MAGI 3体（melchior→balthasar→casper）でコミット前レビューを行う。HIGH指摘ゼロでLGTM。--audit フラグで Codex 監査を追加実行。Trigger: "/magi-fast", "magi-fast", "コミット前レビュー", "ファストレビュー"
---

# MAGI-FAST スキル

MAGI の3体（MELCHIOR→BALTHASAR→CASPER）を順次実行し、コミット前の品質チェックを行う。
HIGH 指摘がゼロになるまでユーザーに修正を促すループの1サイクルを担う。

## 前提

各体は独立して同じ diff を見る（コンテキスト非共有）。
Ollama が使える場合はローカル実行、使えない場合は Haiku にフォールバック。

### オプション: `--audit`

`/magi-fast --audit` で呼び出した場合、ステップ 5 の集計後に Codex 監査を追加実行する。
HIGH/MEDIUM 指摘の妥当性を検証し、`false_positive` 判定の指摘に注記を付けてユーザーに提示する。
（magi-fast はインラインコメントを投稿しないため、false_positive は除外でなく注記扱い）

## ステップ 0: フラグ解析

ユーザーの引数に `--audit` が含まれるか確認し、`$AUDIT_MODE` に保持する:
- `--audit` あり: `AUDIT_MODE=true`
- `--audit` なし: `AUDIT_MODE=false`

## ステップ 1: レビュー対象の取得

以下の優先順位で diff を取得し、`$DIFF` として保持する：

```bash
DIFF=$(git diff --staged 2>/dev/null)
[ -z "$DIFF" ] && DIFF=$(git diff HEAD 2>/dev/null)
# ロールプレイ指示ファイルを除外する（各MAGIでも防御的再フィルタを行う二層構造）
DIFF=$(printf '%s\n' "$DIFF" | bash scripts/magi-diff-filter.sh)
```

差分が空の場合は「ステージ済み差分がありません」と表示して終了する。

## ステップ 2: MELCHIOR 実行（最初）

`/melchior` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
実行が**完全に完了**した後、結果を `$MELCHIOR_RESULT` として保持してからステップ 3 に進む。

## ステップ 3: BALTHASAR 実行（`$MELCHIOR_RESULT` 取得後）

`$MELCHIOR_RESULT` が得られたことを確認してから起動する。
`/balthasar` スキルの手順に従い、同じ `$DIFF` を渡してレビューを実行する。
実行が**完全に完了**した後、結果を `$BALTHASAR_RESULT` として保持してからステップ 4 に進む。

## ステップ 4: CASPER 実行（`$BALTHASAR_RESULT` 取得後）

`$BALTHASAR_RESULT` が得られたことを確認してから起動する。
`/casper` スキルの手順に従い、同じ `$DIFF` を渡してレビューを実行する。
実行が**完全に完了**した後、結果を `$CASPER_RESULT` として保持してからステップ 5 に進む。

## ステップ 5: 結果の集計と判定

3体の結果を統合し、`[HIGH]` 指摘の総数を数える。

```
## MAGI-FAST レビュー結果

---
### MELCHIOR（コード品質・バグ）
<$MELCHIOR_RESULT>

---
### BALTHASAR（設計・アーキテクチャ）
<$BALTHASAR_RESULT>

---
### CASPER（ルール遵守）
<$CASPER_RESULT>

---
## 判定
HIGH 指摘: N 件 / MEDIUM 指摘: M 件 / LOW 指摘: K 件
```

### HIGH が 1 件以上の場合

```
⚠ HIGH 指摘が N 件あります。修正後に /magi-fast を再実行してください。
```

HIGH 指摘の修正は `/codegen` で実装すること。Ollama が使えない場合のみ直接修正する。

### HIGH が 0 件の場合

```
✓ MAGI-FAST: 全体 LGTM。/commit できます。
```

## ステップ 6: Codex 監査（`--audit` 指定時のみ）

`$AUDIT_MODE` が `true` でない場合はこのステップをスキップする。

### 6-1. Finding ID の付与

3体の結果から HIGH/MEDIUM 指摘を抽出し、`M-001`, `M-002`, ... の形式で連番を付与する。

```text
M-001: [HIGH] MELCHIOR — filepath:line — headline
M-002: [MEDIUM] BALTHASAR — filepath:line — headline
...
```

このリストを `$FINDING_LIST` として保持する（plain text）。
HIGH/MEDIUM 指摘が 0 件の場合は Codex 監査をスキップして終了する。

### 6-2. Codex 監査の実行

```bash
MAGI_TMPDIR=$(mktemp -d)
```

`skills/magi-common/references/codex-audit.md`（repo 内）または `~/.claude/skills/magi-common/references/codex-audit.md` を Read ツールで読み込み、記載の手順に従って Codex を呼び出す。

- 入力: `$FINDING_LIST`（finding-list fence）+ `$DIFF`（diff-block fence）
- 出力: `$MAGI_TMPDIR/codex-audit.json`

### 6-3. 結果の表示

`$MAGI_TMPDIR/codex-audit.json` の内容に基づき、ステップ 5 の結果に追記して表示する：

```
---
## Codex 監査結果

| ID | 判定 | 理由（要約） |
|----|------|-------------|
| M-001 | ✅ valid | ... |
| M-002 | 🔕 false_positive | ... |
| M-003 | ❓ needs_human | ... |

false_positive: N件（コミット判断はユーザーに委ねる）
```

- **`AUDIT_SKIPPED`**（Codex 不可）: 「Codex audit skipped: 監査なし」と表示して終了
- **`AUDIT_ERROR`**: エラー旨を表示して終了

```bash
rm -rf "$MAGI_TMPDIR"
```
