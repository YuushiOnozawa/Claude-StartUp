# Traceability Audit: Core 02 — 実働環境で生まれた開発内容の還流経路が未定義

> ステータス: approved（2026-07-11 人間確認済み）
> 監査実施日: 2026-07-11
> 機械的チェック実施者: Claude Sonnet 4.6
> 二次確認実施者: Codex（read-only）

---

## 機械的チェック結果（PROB → REQ → SPEC → IMPL → TEST）

### 漏れチェック（派生先なし）

| チェーン | 結果 |
|---|---|
| PROB → REQ（全 4 件） | ✅ 漏れなし |
| REQ → SPEC（全 8 件） | ✅ 漏れなし |
| SPEC → IMPL（全 7 件、n/a 2 件含む） | ✅ 漏れなし |
| SPEC → TEST（全 7 件、n/a 2 件含む） | ✅ 漏れなし |

### Orphan チェック（派生元なし）

| チェーン | 結果 |
|---|---|
| Orphan IMPL（SPEC 対応なし） | ✅ なし |
| Orphan TEST（SPEC 対応なし） | ✅ なし |
| Orphan map 行（根拠なし） | ✅ なし |

### IMPL 実在確認

| IMPL ID | ファイル | コミット | 実在 |
|---|---|---|---|
| IMPL-02-01 | scripts/sync-whitelist.conf | 6955706 | ✅ |
| IMPL-02-02 | scripts/sync-known-deletions.conf | 6955706 | ✅ |
| IMPL-02-03 | scripts/sync-check.sh | e82ba74 | ✅ |
| IMPL-02-04 | skills/sync-check/SKILL.md | e82ba74 | ✅ |
| IMPL-02-05 | README.md（還流手順セクション L65） | PR #280 | ✅ |

### TEST 結果記録確認

| SPEC | 結果 |
|---|---|
| SPEC-02-01 | **PASS**（2026-07-11 de-git 実施・確認済み） |
| SPEC-02-02 | PASS（TEST-02-02-01〜03） |
| SPEC-02-03 | **10 PASS / 0 FAIL / 0 SKIP**（2026-07-11 shellcheck 再実行済み） |
| SPEC-02-04 | PASS（TEST-02-04-01）+ 手動確認要（TEST-02-04-02） |
| SPEC-02-05 | TEST-02-02-03, TEST-02-03-07 で担保 PASS |
| SPEC-02-06 | n/a（実装しない） |
| SPEC-02-07 | PASS（TEST-02-07-01） |

---

## 指摘事項

| ID | 重大度 | 内容 | Codex 判定 | 最終分類 |
|---|---|---|---|---|
| A-001 | MEDIUM | 受入条件「初回の還流棚卸し + MM ファイル（CLAUDE.md, skills/pr-review/SKILL.md）取捨判断の記録」に対応する SPEC/IMPL/TEST が存在しない | valid | **解消**（2026-07-11 初回棚卸し実施・取捨判断記録済み。reflux-inventory-2026-07-11.md 参照） |
| A-002 | LOW | sync-check.sh は whitelist の include パターンを 3 形式のみ処理し、未知パターンは無警告スキップ（偽陰性） | valid | **保留**（whitelist.conf 変更時の注意事項として記録） |
| A-003 | LOW | compare_recursive で diff がエラーを返したとき、exit 0 になり得る（偽陰性） | valid | **保留**（運用で対処。将来改善候補として記録） |
| A-004 | LOW | known-deletions 判定は add_new_item（新規）のみ適用。変更カテゴリへの適用範囲が仕様に未明記 | valid | **保留**（仕様想定内。SPEC-02-03 への補足追記で対処済み） |

---

## 指摘詳細

### A-001: 受入条件「初回の還流棚卸し + MM ファイル取捨判断の記録」の SPEC/IMPL/TEST 欠如

**Codex 判定**: valid
> 受入条件の初回棚卸し・MM ファイルの取捨判断記録に対応する SPEC/IMPL/TEST はない。実環境確認 TEST-02-03-11 も未実施で、取捨判断の記録を検証する観点は存在しない。

**現状**: requirements.md の受入条件に「初回の還流棚卸しが実施され、MM ファイル（CLAUDE.md、skills/pr-review/SKILL.md）の取捨判断が記録されている」が存在するが、以下がすべて欠如:
- 対応 SPEC（どう棚卸しを実施・記録するかの仕様）
- 対応 IMPL（実施・記録の実装または手順書）
- 対応 TEST（実施・記録の確認）

**影響**: 受入条件が充足されないまま verified になる可能性

**選択肢**:
- 対応: SPEC/IMPL として「初回棚卸し実施・記録」を追加し、手動で実施して記録を残す
- 対象外: 受入条件を「対象外」または「将来対応」として明記し直す（MM ファイルの突合は PROB-02-03 の解消として手動実施済みという扱い）

---

### A-002: sync-check.sh の未知パターン無警告スキップ

**Codex 判定**: valid
> 実装は 3 形式以外の include パターンを解釈・警告しない。仕様は「+ 行を include パスとして処理」とのみ定め、対応形式を限定していないため、設定拡張時に無検知となる余地がある。

**現状**: traceability-map.md の「Step 9 Audit 引継ぎ」に `warn 化を audit で検討` と記録済み

**影響**: Low（将来 whitelist.conf に非対応パターンを追加した場合のみ発現）

**選択肢**:
- 要対応: sync-check.sh に未知パターン検出時の warning 追加（別 PR）
- 保留: whitelist.conf の管理で対処。変更時に注意として README に記載

---

### A-003: compare_recursive でのエラー時分類漏れ

**Codex 判定**: valid
> compare_recursive では diff -rq の終了コード 2（I/O・権限等のエラー）を差分と区別せず、stderr だけが出て stdout に分類対象行がなければ一覧から漏れる。結果として exit 0 になり得る。

**現状**: traceability-map.md の「Step 9 Audit 引継ぎ」に `安全方向（偽陽性）ではないため audit で warn 追加を検討` と記録済み

**影響**: Low（ファイルシステムエラーや権限問題時のみ発現）

**選択肢**:
- 要対応: diff の終了コード 2 を検出して warn カテゴリに追加（別 PR）
- 保留: 現状を許容。エラー時は stderr に出力されているため運用で対処

---

### A-004: known-deletions の適用範囲が仕様に未明記

**Codex 判定**: valid
> known-deletions は add_new_item でしか参照されず、両側に存在して差分がある対象は「要還流（変更）」になる。一方 SPEC-02-03 は既知削除予定リスト掲載ファイルを別カテゴリとする旨のみで、適用範囲を限定していない。

**現状**: traceability-map.md の「Step 9 Audit 引継ぎ」に `仕様想定内・audit でドキュメント化` と記録済み

**影響**: Low（known-deletions のファイルが両側で差分ある場合に「要還流（変更）」として誤表示される可能性）

**選択肢**:
- 対象外（ドキュメント化のみ）: SPEC-02-03 に「known-deletions は新規検知のみに適用」と補足追記
- 要対応: 変更カテゴリにも known-deletions チェックを追加

---

## 意味的チェック

| 観点 | 確認内容 | 結果 |
|---|---|---|
| SPEC は REQ を実現しているか | REQ-02-01〜08 と SPEC-02-01〜07 の対応を確認 | ✅ 全件対応 |
| TEST は SPEC を検証しているか | test-sync-check.sh の fixture テストが SPEC-02-03 の振る舞いを網羅 | ✅（境界条件・異常系含む） |
| SPEC-02-01（de-git）は REQ-02-01 を実現するか | README に手順を記載し、ユーザーが手動実行する形で REQ を充足 | ✅（2026-07-11 de-git 実施・確認済み） |
| PROB-02-03（MM ファイル突合）は解消されているか | 還流検知（SPEC-02-03）でツールは整備された。実際の突合・取捨判断記録も 2026-07-11 に実施済み | ✅（初回棚卸し実施・取捨判断記録済み 2026-07-11。reflux-inventory-2026-07-11.md 参照） |

---

## 最終判定

| 項目 | 判定 |
|---|---|
| 全 REQ に対応 SPEC あり | ✅ |
| 全 SPEC に対応 IMPL または理由あり | ✅ |
| 全 SPEC に対応 TEST または理由あり | ✅ |
| Orphan IMPL/TEST なし | ✅ |
| IMPL 実在確認済み | ✅ |
| verified 可否 | ✅ **verified**（A-001 は 2026-07-11 初回棚卸し実施で解消。A-002〜04 は保留記録済み） |

---

## Codex 二次確認記録

| 項目 | 内容 |
|---|---|
| 実施日 | 2026-07-11 |
| companion バージョン | 1.0.5 |
| 呼び出し方式 | read-only（`task "$(cat ...)"` inline） |
| 結果 | A-001〜A-004 全件 `valid` |
