---
name: traceability-implement
description: Step 6 実装。approved な実装計画の作業単位を既存開発フロー（/dev-flow・/codegen）で実装し、traceability-map に反映する。Trigger: "/traceability-implement", "core-XX を実装", "実装計画を実行"
argument-hint: "<core-XX> [IMPL-XX-NN（省略時は次の未実装項目）]"
---

# TRACEABILITY-IMPLEMENT（Step 6: 実装）

## 前提

対象 core-XX の `implementation-plan.md` が `approved` であること。

## 手順

1. `skills/traceability-common/references/rules.md`（repo 内。なければ `~/.claude/skills/traceability-common/references/rules.md`） を Read し、対象 core-XX と作業単位を特定する
   （指定が無ければ implementation-plan.md の依存順で次の未実装項目を提案）
2. 作業単位を既存フローで実装する:
   - 原則 `/dev-flow` を起動し、implementation-plan.md の該当作業単位 + 対応 SPEC を
     プラン入力として渡す（dev-flow 側の設計レビュー・magi-fast・commit・PR をそのまま使う）
   - 軽微な単発変更は `/codegen` → `/magi-fast` → `/commit`
3. **仕様外の変更をしない**。実装中に仕様変更が必要と判明したら、実装を止めて
   `specification.md` に戻す（status を reviewing に戻し、人間確認後に再開）
4. 完了後に記録する:
   - `implementation-plan.md`: 該当 IMPL のステータス・実装したファイル・PR/コミット参照
   - `traceability-map.md`: IMPL 行に実装参照（PR番号 or コミット）を追記
5. 3点セット更新（README ステータス表 / 全体ボード / map）。
   core 内の全 IMPL が完了したら README のステータスを implemented に更新する

## 完了条件

- 実装項目が SPEC に紐づき、仕様外の変更がない
- 変更理由・対応仕様 ID・実装ファイルが記録され、map から PR まで追跡できる
