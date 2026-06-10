---
name: dev-flow
description: This skill should be used to execute a single-feature development cycle from design planning to PR creation. It guides through: design plan creation, BALTHASAR architectural review, user approval checkpoint, branch/worktree creation, implementation, magi-fast review loop, commit, and PR. Trigger on "/dev-flow" or "dev-flow". Natural language triggers ("〜を作りたい" etc.) are handled by epic-flow which routes here internally.
---

# DEV-FLOW

Single-feature development workflow from plan to PR.

## Phase Overview

| # | Phase | Content | Stop |
|---|-------|---------|------|
| 1 | PLAN | Design plan creation (+ requirement clarification) | |
| 1.5 | BALTHASAR | Architectural review of plan | |
| 2 | CHECK | User approval | ✋ |
| 3 | BRANCH | Branch / worktree creation | |
| 4 | IMPL | Implementation | |
| 5 | REVIEW | magi-fast → fix loop | |
| 6 | COMMIT | Commit | |
| 7 | PR | PR creation | |

For full phase instructions with commands and templates, load `references/phases.md`.

## Post-PR Recommended Flow

```
/pr-review-respond  → respond to human review comments
/magi-hard          → MAGI 5-persona PR review
/magi-fast          → quality check after fixes (as needed)
merge
```
