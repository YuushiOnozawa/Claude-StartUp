---
name: traceability-test
description: Step 8 テスト。仕様ごとのテスト観点を設計・実行し test-plan.md と結果を記録する。Trigger: "/traceability-test", "core-XX のテスト", "テスト計画して"
argument-hint: "<core-XX>"
---

# TRACEABILITY-TEST（Step 8: テスト）

## 前提

対象 core-XX の `specification.md` が `approved` であること（実装完了は必須ではない —
テスト計画は実装前に書いてよい。実行は実装後）。

## 手順

1. `skills/traceability-common/references/rules.md`（repo 内。なければ `~/.claude/skills/traceability-common/references/rules.md`） を Read し、対象 core-XX を特定する
2. `specification.md` の各 SPEC についてテスト観点 TEST-XX-NN を作る:
   - 正常系 / 異常系 / 境界条件（SPEC の境界条件・fail/warn/info 基準と対応させる）
   - 区分を付ける: 自動テスト（bash テストスクリプト等）/ verify / CI / 手動確認
   - テストできない SPEC は「未テスト（理由）」として明示する
3. `test-plan.md` を更新する。既存テスト資産（scripts/test-*.sh、CI）で足りるものは流用と明記
4. 実装済みの場合はテストを実行し、結果（pass/fail・実行日・ログ要点）を test-plan.md に記録する。
   失敗は隠さず記録し、修正が必要なら `/traceability-implement` に戻す
5. `traceability-map.md` に SPEC → TEST の対応を追加する
6. 3点セット更新（README ステータス表 / 全体ボード / map）。
   全 TEST 実行済み・pass なら README のステータスを verified 候補として提示
7. 人間確認: 未テスト仕様と手動確認項目を提示して AskUserQuestion
   →「approved にする / draft のまま / 修正指示」

## 完了条件

- 全 SPEC にテスト観点または未テスト理由がある
- テスト結果が記録され、map に SPEC → TEST が追加されている
