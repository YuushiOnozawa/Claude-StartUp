---
name: magi-fast
description: MAGI 3体（melchior→balthasar→casper）でコミット前レビューを行う。ブロック指摘ゼロでLGTM。Trigger: "/magi-fast", "magi-fast", "コミット前レビュー", "ファストレビュー"
---

# MAGI-FAST スキル

MAGI の3体（MELCHIOR→BALTHASAR→CASPER）を順次実行し、コミット前の品質チェックを行う。
ブロック指摘がゼロになるまでユーザーに修正を促すループの1サイクルを担う。

3体ともDETECTION NOTES契約（v2、severity廃止）を使う。

## 前提

各体は独立して同じ diff を見る（コンテキスト非共有）。
Ollama が使える場合はローカル実行、使えない場合は Haiku にフォールバック。

## ステップ 1: レビュー対象の取得

以下の優先順位で diff を取得し、`$DIFF` として保持する：

```bash
DIFF=$(git diff --staged 2>/dev/null)
[ -z "$DIFF" ] && DIFF=$(git diff HEAD 2>/dev/null)
# ロールプレイ指示ファイルを除外する（各MAGIでも防御的再フィルタを行う二層構造）
DIFF=$(printf '%s\n' "$DIFF" | bash scripts/magi-diff-filter.sh)
```

差分が空の場合は「ステージ済み差分がありません」と表示して終了する。

**この後の全ペルソナ呼び出しで `MAGI_ORCHESTRATED=true` を設定する。**
3体とも自分ではNormalizerを呼ばず生の結果を返す。`magi-fast`がステップ5でまとめて
1回のNormalizer呼び出しにバッチ化する（呼び出し回数削減のため。モデルロード・推論のオーバーヘッドを削減する）。

```bash
MAGI_ORCHESTRATED=true
```

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

### 5-1. 3体のバッチNormalizer呼び出し

MELCHIOR/BALTHASAR/CASPERは`$MAGI_ORCHESTRATED=true`で実行済みのため、生の結果（`$MELCHIOR_RESULT`/`$BALTHASAR_RESULT`/`$CASPER_RESULT`、チャンクヘッダー込み）を返している。1回のバッチ呼び出しにまとめてNormalizerへ渡す。

```bash
MAGI_TMPDIR_NORM=$(mktemp -d)
```

`skills/magi-common/references/normalizer.md`（repo 内）または `~/.claude/skills/magi-common/references/normalizer.md` を Read ツールで読み込み、記載の手順に従ってNormalizerを実行する（手順中の `$MAGI_TMPDIR` は `$MAGI_TMPDIR_NORM` に読み替える）。

- 入力: 3体の生結果を`=== PERSONA: <name> / CHUNK: <path> (<n>) ===`ヘッダーで連結したもの
- 出力: `$MAGI_TMPDIR_NORM/normalizer.json`

失敗（`NORMALIZE_SKIPPED`/`NORMALIZE_ERROR`）した場合は、Haiku fallbackを試みる。それでも失敗する場合は3体すべて未判定として扱い、5-3のフォールバックへ進む。

### 5-2. Codex軽量ゲート判定

正規化に成功した場合、`skills/magi-common/references/codex-fast-gate.md`（repo 内）または `~/.claude/skills/magi-common/references/codex-fast-gate.md` を Read ツールで読み込み、記載の手順に従ってCodexを呼び出す。

```bash
MAGI_TMPDIR_GATE=$(mktemp -d)
```

- 入力: `normalizer.json`の各候補（MELCHIOR/BALTHASAR/CASPER分の`$GATE_INPUT`）+ `$DIFF` + `$SEVERITY_STANDARDS`
- 出力: `$MAGI_TMPDIR_GATE/codex-fast-gate.json`

`$GATE_INPUT` は `normalizer.json` の各候補に `F-001`, `F-002`, ... の形式でIDを付与し、`persona`・`path`・`line`・`headline`・`body`を含めて組み立てる。severityによる事前フィルタはしない。

`$SEVERITY_STANDARDS` は、MELCHIOR/BALTHASAR/CASPERそれぞれの `skills/<persona>/references/review-criteria.md` の `## Severity Standards` 節を、ペルソナ名付きで連結して組み立てる。これは `codex-fast-gate.md` の補助文脈であり、ゲート判定の主基準は同ファイルの汎用 `block`/`defer`/`manual` 基準である。

`verdict=valid`かつ`gate=block`の件数を`$BLOCK_COUNT`、`verdict=valid`かつ`gate=defer`の件数を`$DEFER_COUNT`、`verdict=needs_human`または`gate=manual`の件数を`$MANUAL_COUNT`として保持する。

**ゲート呼び出しが失敗した場合（`FAST_GATE_SKIPPED`/`FAST_GATE_ERROR`）:** 3体すべて未判定として扱い、5-3のフォールバックへ進む。

### 5-3. 結果の表示と判定

```
## MAGI-FAST レビュー結果

---
### MELCHIOR（コード品質・バグ）
<$MELCHIOR_RESULT の要約、または正規化済み候補一覧>

---
### BALTHASAR（設計・アーキテクチャ）
<$BALTHASAR_RESULT の要約、または正規化済み候補一覧>

---
### CASPER（ルール遵守）
<$CASPER_RESULT の要約、または正規化済み候補一覧>

---
## 判定
ブロック指摘: N件 / 要確認: M件 / 見送り: K件
```

### ブロック指摘（`$BLOCK_COUNT`）が 1 件以上の場合

```
⚠ ブロック指摘が N 件あります。修正後に /magi-fast を再実行してください。
```

ブロック指摘の修正は `/codegen` で実装すること。Ollama が使えない場合のみ直接修正する。
`gate=defer`の指摘は表示するがブロック対象にしない。`gate=manual`/`needs_human`の指摘はLGTMを妨げるが自動`/codegen`対象にはしない（ユーザー確認を促す）。

### ブロック指摘が 0 件、かつ `$MANUAL_COUNT` も 0 件の場合

```
✓ MAGI-FAST: 全体 LGTM。/commit できます。
```

### 5-1または5-2で判定に失敗した場合のフォールバック

```
⚠ ゲート判定が失敗したため、いずれの体の指摘も判定できていません。
LGTMは出しません。/magi-hard での精査を推奨します。
理由: <NORMALIZE_ERROR/FAST_GATE_ERROR等>
```

`magi-fast` は `codex-audit.md` によるvalid/false_positive/needs_humanの精査を行わない。精査が必要な場合は `magi-hard` に委ねる。
