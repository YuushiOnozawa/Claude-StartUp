---
name: traceability-impl-plan
description: Step 5 実装項目策定。approved な仕様から変更ファイル・作業単位・PR分割・依存関係を整理し implementation-plan.md を更新する。Trigger: "/traceability-impl-plan", "実装計画して", "core-XX の実装項目"
argument-hint: "<core-XX>"
---

# TRACEABILITY-IMPL-PLAN（Step 5: 実装項目策定）

## 前提

対象 core-XX の `specification.md` が `approved` であること。draft なら中断して案内する。

## 手順

1. `skills/traceability-common/references/rules.md`（repo 内。なければ `~/.claude/skills/traceability-common/references/rules.md`） を Read し、対象 core-XX を特定する
2. `specification.md`（approved 仕様）と変更対象になりそうな既存実装を Read する
3. `implementation-plan.md` を更新する:
   - 仕様ごとに実装項目 IMPL-XX-NN を対応させる（対応しない SPEC には未実装理由）
   - 変更候補ファイルの明示 / 1 PR で完結する作業単位への分割 / PR 間・core 間の依存関係
   - 実装前に決めるべきこと（未確定のまま実装に入らない）
   - 各作業単位に実行方法を付記: 原則 `/dev-flow`（この repo の標準フロー）、
     軽微な単発変更のみ `/codegen` + `/magi-fast` + `/commit` 直列
4. `traceability-map.md` に SPEC → IMPL の対応を追加する
5. 3点セット更新（README ステータス表 / 全体ボード / map）
6. 人間確認ポイントを提示して AskUserQuestion:
   実装単位が大きすぎないか / PR 分割が妥当か / 依存関係が明確か
   →「approved にする / draft のまま / 修正指示」

## 完了条件

- 全 IMPL が SPEC に紐づき、変更対象ファイルが明示されている
- PR 分割可能な単位になっており、依存関係が書かれている
- map に SPEC → IMPL が追加されている
