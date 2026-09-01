---
name: dev-flow
description: This skill should be used to execute a single-feature development cycle from design planning to PR creation. It guides through: design plan creation, Codex design review (BALTHASAR fallback), user approval checkpoint, branch/worktree creation, implementation, review-fast review loop, commit, and PR. Trigger on "/dev-flow" or "dev-flow". Natural language triggers ("〜を作りたい" etc.) are handled by epic-flow which routes here internally.
---

# DEV-FLOW

Single-feature development workflow from plan to PR.

## Phase Overview

| # | Phase | Content | Stop |
|---|-------|---------|------|
| 1 | PLAN | /grill-me による要件深掘り → 設計プラン作成 | |
| 1.5 | DESIGN REVIEW | Codex design review of plan (BALTHASAR fallback) | |
| 2 | CHECK | User approval | ✋ |
| 3 | BRANCH | Branch / worktree creation | |
| 4 | IMPL | Implementation | |
| 5 | REVIEW | `/review-fast`（backend選択）→ envelope 判定 → fix loop | |
| 6 | COMMIT | Commit | |
| 7 | PR | PR creation | |

For full phase instructions with commands and templates, load `references/phases.md`.

## Post-PR Recommended Flow

```
/pr-review-respond  → respond to human review comments
/review-hard（backend選択） → PR review（レビューエンジンをどちらか一方選択。両方の実行は不要）
/review-fast          → quality check after fixes (as needed、backend は選択したものを使用)
merge
/finished-pr        → post-merge cleanup (main pull, Issue close, branch delete)
```
