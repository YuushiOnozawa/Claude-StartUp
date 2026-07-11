# Implementation Plan: Core 04 — 第二の脳・プロジェクト横断想起の運用仕様化

> ステータス: approved（2026-07-08 Codex レビュー対応済み）
> 対応 specification: approved 2026-07-08

---

## 変更対象ファイル

| ファイル | 変更種別 | 対応 SPEC |
|---|---|---|
| `skills/inbox/SKILL.md` | 新規 | SPEC-04-01 |
| `skills/inbox/references/store-layout.md` | 新規 | SPEC-04-03 |
| `skills/compact-prep/SKILL.md` | 追記（経験カード形式セクション） | SPEC-04-02 |
| SPEC-04-04（auto-recall 実装） | **実装なし**（実装ゲート未達） | SPEC-04-04 |

---

## 実装前に決めるべきこと

**blockers: なし。**

SPEC-04 の全 SPEC に blocker なし。

**SPEC-04-04 の実装順序制約（blockerではない）:**

auto-recall（SPEC-04-04）は「実装条件ゲート」を人間が確認後に着手する。ゲート判定ファイル（`docs/traceability/core-04-second-brain-recall/auto-recall-go.md`）が存在しないため、本 impl-plan では「ゲート通過後に別途 PR」と記録するにとどめる。

ゲート条件（SPEC-04-04 より）:
1. `store/distilled/ja/` 配下の `.md` ファイルが 10件以上
2. `/inbox` スキルが 5回以上エラーなく完了
3. 人間が `auto-recall-go.md` を作成して GO を宣言

---

## 作業単位と PR 分割

### PR-A: `/inbox` スキル新設

**対応 SPEC:** SPEC-04-01, SPEC-04-03  
**対応 IMPL:** IMPL-04-01, IMPL-04-02  
**変更ファイル:** `skills/inbox/SKILL.md`（新規）, `skills/inbox/references/store-layout.md`（新規）  
**実行方法:** `/dev-flow`（新規スキル + 参照ドキュメント）  
**依存:** なし（独立）

**外部確定済み依存（SPEC-04-03 前提条件 — 他 core で解決済み）:**
- SPEC-03.2-03: store 基点は `~/.local/share/knowledge-rag/store`（ローカル保存）
- SPEC-03.2-05: lessons-learned もローカル保存（FUSE 書き込み廃止）
- SPEC-01-03: pCloud への書き込みは `pcloud-sync.sh` のみ（FUSE マウント経由禁止）

PR-A に SPEC-04-01 と SPEC-04-03 を同一 PR とする理由: `store-layout.md` は `/inbox` スキルが参照するデータ設計文書であり、スキルと分離できない単一の関心事（「inbox スキルとそのデータ設計」）。

#### IMPL-04-01: `skills/inbox/SKILL.md` 新規作成

`/inbox` スキル（手動実行 v1）を実装する。SKILL.md に以下のフローを定義する:

1. **入力読み取り**: `$HOME/.local/share/knowledge-rag/store/vault/_inbox/` 内の `.md` ファイルを列挙
2. **未処理フィルタ**: `store/vault/_inbox-ledger.md` の `processed: true` エントリをスキップ（`[SKIP] <slug>`）
3. **調査実行（未処理エントリごと）**:
   - URL が含まれる場合: `WebFetch` / `WebSearch` で取得・要約
   - メモのみの場合: knowledge-rag 登録用に整形
4. **knowledge 還流**: `mcp__knowledge-rag__add_document`（`filepath: inbox/<YYYY-MM-DD>-<slug>.md`、`category: inbox`）
5. **台帳更新**: `store/vault/_inbox-ledger.md` に処理完了を記録
6. **禁止**: `store/vault/_inbox/` の Obsidian ノート本体は書き換えない

**境界条件の実装:**

| 条件 | 実装 |
|---|---|
| inbox が空 | `[INFO] inbox は空です` を出力して正常終了 |
| 台帳に processed: true のエントリ | `[SKIP] <slug>` を出力してスキップ |
| WebFetch 失敗 | `[WARN] <URL> の取得失敗。手動確認を推奨` 出力。台帳は `processed: false` のまま |
| knowledge-rag 登録失敗 | `[WARN] knowledge 登録失敗: <slug>` 出力。台帳は `processed: false` のまま |
| `_inbox-ledger.md` が存在しない | ヘッダー行と区切り行のみで新規作成してから処理継続 |

**デプロイ（PR マージ後）:**

```bash
cp -r skills/inbox/ ~/.claude/skills/inbox/
```

#### IMPL-04-02: `skills/inbox/references/store-layout.md` 新規作成

SPEC-04-03 のディレクトリ責務定義を `/inbox` スキルの参照ドキュメントとして記録する。

内容:
- `STORE_BASE="$HOME/.local/share/knowledge-rag/store"` の定義
- ディレクトリ責務表（distilled/ja, distilled/en, knowledge/, vault/, vault/_inbox/, vault/_inbox-ledger.md）
- `_inbox-ledger.md` フォーマット（フィールド定義・操作ルール）

#### 検証手順（PR 内 — マージ前に実行）

```bash
# IMPL-04-01: スキル存在・フロー定義確認
test -f skills/inbox/SKILL.md && echo "OK: SKILL.md 存在" || echo "FAIL"
grep -q "_inbox-ledger" skills/inbox/SKILL.md && echo "OK: 台帳処理記載" || echo "FAIL"
grep -q "add_document\|knowledge-rag\|知識.*還流\|knowledge.*還流" skills/inbox/SKILL.md && echo "OK: knowledge 還流記載" || echo "FAIL"
grep -q "processed" skills/inbox/SKILL.md && echo "OK: 未処理フィルタ記載" || echo "FAIL"
grep -q "書き換えない\|禁止\|読み取り専用\|書き込み.*禁止" skills/inbox/SKILL.md && echo "OK: 書き換え禁止記載" || echo "FAIL"
grep -q "WARN.*取得失敗\|取得失敗.*WARN\|WebFetch.*失敗\|失敗.*WebFetch" skills/inbox/SKILL.md && echo "OK: WebFetch 失敗時 WARN 記載" || echo "FAIL"

# IMPL-04-02: store-layout.md 存在・内容確認
test -f skills/inbox/references/store-layout.md && echo "OK: store-layout.md 存在" || echo "FAIL"
grep -q "STORE_BASE\|knowledge-rag/store" skills/inbox/references/store-layout.md && echo "OK: STORE_BASE 記載" || echo "FAIL"
grep -q "distilled/ja" skills/inbox/references/store-layout.md && echo "OK: distilled/ja 記載" || echo "FAIL"
grep -q "_inbox-ledger" skills/inbox/references/store-layout.md && echo "OK: 台帳フォーマット記載" || echo "FAIL"
```

#### デプロイ確認（PR マージ後に実行）

```bash
# cp -r skills/inbox/ ~/.claude/skills/inbox/ 実行後に確認
diff -r skills/inbox/ ~/.claude/skills/inbox/ > /dev/null 2>&1 && echo "OK: ~/.claude へデプロイ済み" || echo "FAIL: CWD と ~/.claude が不一致"
```

---

### PR-B: `compact-prep` 経験カード形式追加

**対応 SPEC:** SPEC-04-02  
**対応 IMPL:** IMPL-04-03  
**変更ファイル:** `skills/compact-prep/SKILL.md`（追記）  
**実行方法:** `/codegen` + `/magi-fast` + `/commit`（既存スキルへの追記）  
**依存:** なし（独立）

#### IMPL-04-03: `skills/compact-prep/SKILL.md` に経験カード形式セクション追加

「保存内容」セクションの後に「経験カード出力」セクションを追加する:

```markdown
## 経験カード出力

`/compact` 後、セッション完了時に以下の形式で経験カードを生成する。

### 出力先
- 日本語カード: `$HOME/.local/share/knowledge-rag/store/distilled/ja/<YYYY-MM-DD>-<slug>.md`
- 英語シャドウ: `$HOME/.local/share/knowledge-rag/store/distilled/en/<YYYY-MM-DD>-<slug>.md`

### 経験カード形式（全フィールド必須）

```markdown
---
title: <セッションタイトルまたはタスク概要>
date: <YYYY-MM-DD>
tags: [<技術タグ1>, <技術タグ2>]
outcome: success | partial | failed
---

## 状況
<どのような問題・タスクに取り組んでいたか。背景・制約を含む>

## やったこと
<実際に行った操作・判断・コマンド。箇条書き可>

## 結果
<何が達成されたか。エラー・失敗の場合はその内容>

## 判断理由
<なぜそのアプローチを選んだか。代替案との比較があれば記述>

## outcome
<success / partial / failed とその理由一文>
```

### 境界条件
- セッションが短い（transcript が 500 文字未満）: 「状況: 情報不足（トランスクリプト不足）」として出力し、他フィールドをプレースホルダーで補完
- outcome が判定できない場合: `partial` をデフォルトとする
- 英語翻訳が困難な専門用語: 原語（日本語）のまま記述し、説明を付記する
```

**デプロイ（PR マージ後）:**

```bash
cp skills/compact-prep/SKILL.md ~/.claude/skills/compact-prep/SKILL.md
```

#### 検証手順（PR 内 — マージ前に実行）

```bash
# 経験カード形式の全フィールド存在確認
grep -q "^## 状況" skills/compact-prep/SKILL.md && echo "OK: 状況" || echo "FAIL"
grep -q "^## やったこと" skills/compact-prep/SKILL.md && echo "OK: やったこと" || echo "FAIL"
grep -q "^## 結果" skills/compact-prep/SKILL.md && echo "OK: 結果" || echo "FAIL"
grep -q "^## 判断理由" skills/compact-prep/SKILL.md && echo "OK: 判断理由" || echo "FAIL"
grep -q "^## outcome" skills/compact-prep/SKILL.md && echo "OK: outcome" || echo "FAIL"

# frontmatter フィールド確認
grep -q "^title:" skills/compact-prep/SKILL.md && echo "OK: title フィールド" || echo "FAIL"
grep -q "^tags:" skills/compact-prep/SKILL.md && echo "OK: tags フィールド" || echo "FAIL"
grep -q "outcome:.*success\|success.*partial.*failed" skills/compact-prep/SKILL.md && echo "OK: outcome 値定義" || echo "FAIL"

# 出力先確認
grep -q "distilled/ja" skills/compact-prep/SKILL.md && echo "OK: 日本語出力先記載" || echo "FAIL"
grep -q "distilled/en\|英語シャドウ" skills/compact-prep/SKILL.md && echo "OK: 英語シャドウ記載" || echo "FAIL"

# 境界条件記載確認
grep -q "500.*文字\|トランスクリプト不足" skills/compact-prep/SKILL.md && echo "OK: 短セッション境界条件" || echo "FAIL"

# 追記のみ確認（削除行なし）
_del=$(git diff HEAD -- skills/compact-prep/SKILL.md | grep -c '^-[^-]' 2>/dev/null || echo 0)
test "$_del" -eq 0 && echo "OK: 削除行なし（追記のみ確認）" || echo "FAIL: ${_del} 行削除"
```

#### デプロイ確認（PR マージ後に実行）

```bash
# cp skills/compact-prep/SKILL.md ~/.claude/skills/compact-prep/SKILL.md 実行後に確認
diff skills/compact-prep/SKILL.md ~/.claude/skills/compact-prep/SKILL.md > /dev/null 2>&1 && echo "OK: ~/.claude へデプロイ済み" || echo "FAIL: CWD と ~/.claude が不一致"
```

---

### SPEC-04-04: auto-recall — 実装ゲート未達のため実装なし

**対応 IMPL:** IMPL-04-04（留保）  
**現状:** 実装条件ゲート（蒸留カード 10件以上・/inbox 5回完了・人間 GO 宣言）を未達  
**実装タイミング:** `docs/traceability/core-04-second-brain-recall/auto-recall-go.md` 作成後に別途 PR  
**設計仕様:** `specification.md` の SPEC-04-04 セクションに完全記述済み

---

## PR 依存関係グラフ

```
PR-A (/inbox スキル新設)     [独立]
PR-B (compact-prep 経験カード) [独立]
IMPL-04-04 (auto-recall)     [ゲート通過後、将来 PR]
```

- PR-A と PR-B は完全独立。任意の順で実施可
- PR-A → PR-B の順が自然（/inbox で生成したカードを compact-prep が扱うフロー順）

---

## SPEC → IMPL 対応表

| SPEC ID | IMPL ID | PR | 備考 |
|---|---|---|---|
| SPEC-04-01（/inbox スキル実装） | IMPL-04-01 | PR-A | デプロイコマンド必須 |
| SPEC-04-02（経験カード形式定義） | IMPL-04-03 | PR-B | デプロイコマンド必須 |
| SPEC-04-03（store/vault 責務定義） | IMPL-04-02 | PR-A | IMPL-04-01 と同 PR（単一関心事） |
| SPEC-04-04（auto-recall 設計） | IMPL-04-04（留保） | 将来 PR | 実装ゲート通過後に着手 |

## 注意

- `skills/inbox/` と `skills/compact-prep/` は CWD が正。直接 `~/.claude/` は変更しない（CLAUDE.local.md ルール）。PR マージ後に `cp` でデプロイする
- `store/vault/_inbox-ledger.md` は `/inbox` スキルの初回実行時に自動作成される。事前作成不要
- SPEC-04-04 は specification.md に設計仕様が完全記述済み。実装ゲート通過まで impl は不要
- UND-04-02（英語シャドウ運用方針の最終確定）は A/B 評価後。現時点は「両方出力」で実装する。評価結果は `docs/traceability/core-04-second-brain-recall/english-shadow-decision.md` に記録し、その後 specification.md を改訂して解決とする
