---
name: traceability-spec
description: Step 4 仕様化。approved な要求をテスト可能な仕様に落とし specification.md を更新する。Trigger: "/traceability-spec", "仕様化して", "core-XX の仕様"
argument-hint: "<core-XX>"
---

# TRACEABILITY-SPEC（Step 4: 仕様化）

## 前提

対象 core-XX の `requirements.md` が `approved` であること。draft なら中断し
`/traceability-requirements` の人間確認を先に案内する。

## 手順

1. `skills/traceability-common/references/rules.md`（repo 内。なければ `~/.claude/skills/traceability-common/references/rules.md`） を Read し、対象 core-XX を特定する
2. `requirements.md`（approved 要求）と関連する既存実装（該当ファイルの現状）を Read する
3. `specification.md` を更新する:
   - 要求ごとに具体的な振る舞いを SPEC-XX-NN として書く（**テスト可能な粒度**）
   - 入力 / 出力 / 状態 / 例外 / 境界条件
   - fail / warn / info の判定基準候補
   - 自動化対象と手動確認対象の区別
   - 未確定事項は「未確定」セクションに分離する（仕様に混ぜない）
4. `traceability-map.md` に REQ → SPEC の対応を追加する
5. 3点セット更新（README ステータス表 / 全体ボード / map）
6. 人間確認ポイントを提示して AskUserQuestion:
   仕様がテスト可能か / fail・warn・info 基準が妥当か / 未確定事項の残し方が妥当か
   →「approved にする / draft のまま / 修正指示」

## 完了条件

- 全 SPEC が REQ に紐づき、境界条件が書かれている
- 未確定事項が分離されている
- map に REQ → SPEC が追加されている
