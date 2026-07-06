---
name: traceability-init-docs
description: Step 2 核問題ごとのフォルダ・draft ドキュメント生成。分類結果から docs/traceability/core-XX-<name>/ 一式と全体ボードを生成する。Trigger: "/traceability-init-docs", "核問題フォルダ作成", "トレサビ雛形生成"
argument-hint: "<分類ドキュメントパス（省略時は docs/planning/ から検出）>"
---

# TRACEABILITY-INIT-DOCS（Step 2: フォルダ・draft ドキュメント生成）

## 手順

1. `skills/traceability-common/references/rules.md`（repo 内。なければ `~/.claude/skills/traceability-common/references/rules.md`） を Read する
2. 分類ドキュメント（docs/planning/）を Read し、核問題一覧を取得する
3. 各核問題について `docs/traceability/core-XX-<name>/` を作成し、以下を生成する:
   - `README.md` — 核問題名・関連項目・関連目的・問題概要・分類・confidence・人間確認点 +
     ステータス表（requirements〜map = draft、design-review / audit = todo）
   - `requirements.md` / `specification.md` / `implementation-plan.md` / `test-plan.md` —
     分類詳細から転記できる範囲のたたき台 + 「(draft) 未確定」ヘッダ
   - `traceability-map.md` — PROB-XX-NN の問題行のみ記載（対応列は空）
   - design-review.md / traceability-audit.md は**この時点では作らない**（Step 7/9 で作成）
4. `/traceability-board-update` を実行して全体ボードを生成・更新する
5. 生成結果の一覧を提示する（この Step は生成のみのため approve 確認は不要）

## 完了条件

- 全核問題にフォルダと 6 ファイルが存在し、すべて draft 扱いである
- 全体ボードに全核問題が載っている
- 既存フォルダがある場合は上書きせずスキップし、その旨を報告する
