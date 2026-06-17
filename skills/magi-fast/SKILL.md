---
name: magi-fast
description: MAGI 3体（melchior→balthasar→casper）でコミット前レビューを行う。HIGH指摘ゼロでLGTM。Trigger: "/magi-fast", "magi-fast", "コミット前レビュー", "ファストレビュー"
---

# MAGI-FAST スキル

MAGI の3体（MELCHIOR→BALTHASAR→CASPER）を順次実行し、コミット前の品質チェックを行う。
HIGH 指摘がゼロになるまでユーザーに修正を促すループの1サイクルを担う。

## 前提

各体は独立して同じ diff を見る（コンテキスト非共有）。
Ollama が使える場合はローカル実行、使えない場合は Haiku にフォールバック。

## ステップ 1: レビュー対象の取得

以下の優先順位で diff を取得し、`$DIFF` として保持する：

```bash
DIFF=$(git diff --staged 2>/dev/null)
[ -z "$DIFF" ] && DIFF=$(git diff HEAD 2>/dev/null)
# ロールプレイ指示ファイルを除外する（各MAGIでも防御的再フィルタを行う二層構造）
DIFF=$(printf '%s\n' "$DIFF" | awk '/^diff --git/{skip=($0 ~ /SKILL\.md |CLAUDE\.md |\/agents\/.*\.md|\/references\/.*\.md/)} !skip')
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
