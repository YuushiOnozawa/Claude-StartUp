---
name: magi-fast
description: MAGI 3体（melchior→balthasar→casper）でコミット前レビューを行う。ブロック指摘ゼロでLGTM。--audit フラグでCASPER分のCodex監査を追加実行。Trigger: "/magi-fast", "magi-fast", "コミット前レビュー", "ファストレビュー"
---

# MAGI-FAST スキル

MAGI の3体（MELCHIOR→BALTHASAR→CASPER）を順次実行し、コミット前の品質チェックを行う。
ブロック指摘がゼロになるまでユーザーに修正を促すループの1サイクルを担う。

MELCHIOR/BALTHASARはDETECTION NOTES契約（v2、severity廃止）、CASPERは従来通りseverity付き契約（v1）を使う。

## 前提

各体は独立して同じ diff を見る（コンテキスト非共有）。
Ollama が使える場合はローカル実行、使えない場合は Haiku にフォールバック。

### `--audit`オプションの意味（v2化に伴い暫定運用、ユーザー確認待ち）

**MELCHIOR/BALTHASAR（v2）分の妥当性・ブロック可否判定（`codex-fast-gate.md`）は`--audit`の有無に関わらず常時実行する。** v2にはseverityが無く、事前フィルタとして機能する情報が無いため、ゲート判定自体を省略できない。

`/magi-fast --audit` で呼び出した場合は、これに加えてCASPER（v1）分のHIGH/MEDIUM指摘についてもCodex監査（`codex-audit.md`）を追加実行する（従来の`--audit`の対象範囲そのまま、CASPERのみに限定）。

**この`--audit`の意味変更（「Codexを全く呼ばない」から「MELCHIOR/BALTHASAR分は常時Codexを呼ぶ」への変化）はユーザー未確認。** 命令文言・フラグ名の妥当性は次回のユーザー確認（設計プランのPhase F）で最終決定する。

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

**この後の全ペルソナ呼び出しで `MAGI_ORCHESTRATED=true` を設定する。**
MELCHIOR/BALTHASAR（v2）は自分ではNormalizerを呼ばず生の結果を返す。`magi-fast`が
ステップ5でまとめて1回のNormalizer呼び出しにバッチ化する（呼び出し回数削減のため。モデルロード・推論のオーバーヘッドを削減する）。
CASPER（v1）にはこの設定は影響しない。

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

### 5-1. MELCHIOR/BALTHASARのバッチNormalizer呼び出し

MELCHIOR/BALTHASARは`$MAGI_ORCHESTRATED=true`で実行済みのため、生の結果（`$MELCHIOR_RESULT`/`$BALTHASAR_RESULT`、チャンクヘッダー込み）を返している。1回のバッチ呼び出しにまとめてNormalizerへ渡す。

```bash
MAGI_TMPDIR_NORM=$(mktemp -d)
```

`skills/magi-common/references/normalizer.md`（repo 内）または `~/.claude/skills/magi-common/references/normalizer.md` を Read ツールで読み込み、記載の手順に従ってNormalizerを実行する（手順中の `$MAGI_TMPDIR` は `$MAGI_TMPDIR_NORM` に読み替える）。

- 入力: MELCHIOR/BALTHASARの生結果を`=== PERSONA: <name> / CHUNK: <path> (<n>) ===`ヘッダーで連結したもの
- 出力: `$MAGI_TMPDIR_NORM/normalizer.json`

失敗（`NORMALIZE_SKIPPED`/`NORMALIZE_ERROR`）した場合は、Haiku fallbackを試みる。それでも失敗する場合は「MELCHIOR/BALTHASAR分は未判定」として扱い、5-3のフォールバックへ進む（CASPERの判定は影響を受けない）。

### 5-2. Codex軽量ゲート判定

正規化に成功した場合、`skills/magi-common/references/codex-fast-gate.md`（repo 内）または `~/.claude/skills/magi-common/references/codex-fast-gate.md` を Read ツールで読み込み、記載の手順に従ってCodexを呼び出す。

```bash
MAGI_TMPDIR_GATE=$(mktemp -d)
```

- 入力: `normalizer.json`の各候補（`$GATE_INPUT`）+ `$DIFF`
- 出力: `$MAGI_TMPDIR_GATE/codex-fast-gate.json`

`verdict=valid`かつ`gate=block`の件数を`$BLOCK_COUNT_V2`、`verdict=valid`かつ`gate=defer`の件数を`$DEFER_COUNT_V2`、`verdict=needs_human`または`gate=manual`の件数を`$MANUAL_COUNT_V2`として保持する。

**ゲート呼び出しが失敗した場合（`FAST_GATE_SKIPPED`/`FAST_GATE_ERROR`）:** v2候補が未判定のまま、CASPERの`[HIGH]=0`だけでLGTMを出してはならない。5-3のフォールバックへ進む。

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
<$CASPER_RESULT>

---
## 判定
CASPER HIGH指摘: N件 / MEDIUM指摘: M件 / LOW指摘: K件
MELCHIOR/BALTHASAR ブロック指摘: N件 / 要検討: M件 / 見送り: K件
```

`$BLOCK_COUNT_TOTAL = CASPERのHIGH件数 + $BLOCK_COUNT_V2` を計算する。

### ブロック指摘（`$BLOCK_COUNT_TOTAL`）が 1 件以上の場合

```
⚠ ブロック指摘が N 件あります。修正後に /magi-fast を再実行してください。
```

ブロック指摘の修正は `/codegen` で実装すること。Ollama が使えない場合のみ直接修正する。
`gate=defer`の指摘は表示するがブロック対象にしない。`gate=manual`/`needs_human`の指摘はLGTMを妨げるが自動`/codegen`対象にはしない（ユーザー確認を促す）。

### ブロック指摘が 0 件、かつ `$MANUAL_COUNT_V2` も 0 件の場合

```
✓ MAGI-FAST: 全体 LGTM。/commit できます。
```

### 5-2でゲート判定に失敗した場合のフォールバック

CASPERの`[HIGH]`件数に関わらずLGTMを出さない。

```
⚠ MELCHIOR/BALTHASAR分のCodexゲート判定が未実行です（理由: <NORMALIZE_ERROR/FAST_GATE_ERROR等>）。
CASPER HIGH指摘: N件（こちらのみ判定済み）
v2候補（MELCHIOR/BALTHASAR）は未判定のため、LGTMは出しません。/magi-hard での精査を推奨します。
```

## ステップ 6: CASPER分のCodex 監査（`--audit` 指定時のみ）

`$AUDIT_MODE` が `true` でない場合はこのステップをスキップする。

**対象はCASPER（v1）分のみ。** MELCHIOR/BALTHASAR（v2）分はステップ5-2の`codex-fast-gate.md`で常時判定済みのため、ここでは扱わない。

### 6-1. Finding ID の付与

CASPERの結果から HIGH/MEDIUM 指摘を抽出し、`M-001`, `M-002`, ... の形式で連番を付与する。

```text
M-001: [HIGH] CASPER — filepath:line — headline
M-002: [MEDIUM] CASPER — filepath:line — headline
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

監査結果は `codex-audit.md`「呼び出し元への契約」の成功条件を**この側でも検証する**こと。
検証を省略すると、産出側の変更で監査結果が静かに欠落しても気づけない。

成功条件を満たさない場合は上表を出さず、以下のいずれかを表示する。**監査していないものを
「監査済み」として見せない。**

```
---
## Codex 監査結果

⚠ 監査を実行できませんでした（理由: <AUDIT_SKIPPED / AUDIT_ERROR の別と message>）
MAGI の指摘は未監査です。誤検知が含まれている可能性を前提に確認してください。
raw 出力: $MAGI_TMPDIR/codex-audit-raw.txt
```

| ケース | 表示内容 |
|---|---|
| `AUDIT_SKIPPED`（Codex 不可・ファイル不在） | 「Codex audit skipped: 監査なし」+ 未監査である旨 |
| `AUDIT_ERROR`（error object・抽出/検証失敗） | `message` と raw 出力のパス + 未監査である旨 |

`magi-fast` は投稿経路を持たないため、未監査でも結果表示は続行する。

```bash
# 監査が成功した場合のみ削除する。失敗時は raw 出力を確認できるよう残す
rm -rf "$MAGI_TMPDIR"
```
