---
name: dev-flow-fast
description: "Codex中心の高速開発フロー。Phase 5のレビューではMAGI-FASTを使わない（PR後の追加確認として任意に使うことは妨げない）。ローカル環境が非力な場合の高速ルート。Trigger: \"/dev-flow-fast\", \"dev-flow-fast\", \"高速開発フロー\", \"Codexだけでレビュー\""
---

# DEV-FLOW-FAST

Codex中心の高速開発フロー。Single-feature development workflow from plan to PR.

## Phase Overview

| # | Phase | Content | Stop |
|---|-------|---------|------|
| 1 | PLAN | /grill-me による要件深掘り → 設計プラン作成 | |
| 1.5 | DESIGN REVIEW | Codex design review of plan (BALTHASAR fallback) | |
| 2 | CHECK | User approval | ✋ |
| 3 | BRANCH | Branch / worktree creation | |
| 4 | IMPL | Implementation | |
| 5 | REVIEW | Codex敵対的レビュー → 指摘ゼロまで修正ループ | |
| 6 | COMMIT | Commit | |
| 7 | PR | PR creation | |

For full phase instructions with commands and templates, load `references/phases.md`.

## Post-PR Recommended Flow

```
/pr-review-respond  → respond to human review comments
/magi-hard          → MAGI 6-persona PR review
/magi-fast          → quality check after fixes (as needed)
merge
/finished-pr        → post-merge cleanup (main pull, Issue close, branch delete)
```

> **運用メモ**: このルートはCodex単体レビューのため、検出と監査が同一エンジンという構造的な制約がある。実測ベンチマーク(`docs/magi-vs-codex-benchmark-2026-08-18.md`)では、現行MAGIのローカルモデル生出力はfalse positiveが大半かつ大規模diffで完走しないケースがあった一方、Codex単体はMAGIが見落とした入力境界の問題を検出する等、精度面で優位だった。低リスク・時短優先の変更に向く。認証認可・データ移行・並行処理・外部境界・セキュリティ等の高リスク変更は、通常の`/dev-flow`(MAGI-FAST)または事後の`/magi-hard`併用を検討すること。
`docs/codex-orchestrated-adaptive-review-plan-2026-08-18.md` は、観点別専門モデル・model registry等を含む将来の拡張案（未実装）であり、このスキルはその計画を実装したものではない。このスキルはCodex単体による汎用的な敵対的レビューであり、MAGI-FAST/HARDの各ペルソナ観点を機械的に継承するものではない。MELCHIOR等をOllama等で個別に呼び出すことはしない（model registry・専門ローカルモデル呼び出しは対象外）。一方、Codexへの単一プロンプト内では6ペルソナ（MELCHIOR/BALTHASAR/CASPER/METATRON/SANDALPHON/LELIEL）の観点を明示的に列挙し、各指摘に`persona`タグを付与させる構造化を行う。
