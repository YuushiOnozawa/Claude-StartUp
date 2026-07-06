---
name: traceability-design-review
description: Step 7 設計レビュー。要求↔仕様↔実装計画の整合・過剰/不足実装・運用影響をレビューし design-review.md を作成する。Codex 優先（flow-common 共通手順）。Trigger: "/traceability-design-review", "core-XX の設計レビュー"
argument-hint: "<core-XX>"
---

# TRACEABILITY-DESIGN-REVIEW（Step 7: 設計レビュー）

実装前（impl-plan approved 後）または実装後に実行する。

## 手順

1. `skills/traceability-common/references/rules.md`（repo 内。なければ `~/.claude/skills/traceability-common/references/rules.md`） を Read し、対象 core-XX を特定する
2. `requirements.md` / `specification.md` / `implementation-plan.md`（実装後なら差分も）を Read する
3. レビューは `skills/flow-common/references/design-review.md`（repo 内。なければ `~/.claude/skills/flow-common/references/design-review.md`） の共通手順（Codex 優先、
   BALTHASAR フォールバック）を使う。変数設定:
   - `PLAN_TEXT` = 仕様 + 実装計画の要点（REQ/SPEC/IMPL の ID 付きで渡す）
   - `REVIEW_CONTEXT` = 核問題の README 概要
   - `REVIEW_CONSTRAINTS` = 「対象外」セクションと承認済み要求（変更禁止領域として渡す）
4. レビュー観点（プロンプトに含める）:
   要求と仕様のズレ / 仕様と実装項目のズレ / 過剰実装・不足実装・曖昧仕様 /
   後方互換性 / 運用影響 / セキュリティ影響
5. `design-review.md` を新規作成し、指摘を 修正済み / 保留 / 対象外 に分類して記録する
   （レビュー実施者 = Codex / BALTHASAR も記録）
6. HIGH 相当の指摘は該当ドキュメントへ反映し、status を reviewing に戻す
7. 3点セット更新（README ステータス表 / 全体ボード / map）
8. 人間確認: 仕様漏れ・過剰実装・互換性の残指摘を提示して AskUserQuestion
   →「approved にする / draft のまま / 修正指示」

## 完了条件

- 重大な仕様漏れがない、または blocked として明記されている
- 全指摘が 修正済み / 保留 / 対象外 に分類されている
