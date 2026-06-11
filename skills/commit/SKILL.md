---
name: commit
description: Git commit workflow. Use every time the user asks to commit, record changes, or save to git history. Never run git commit directly — always use this skill. Handles branch safety, staging, commit message drafting, and Co-Authored-By attribution. Trigger: "コミット", "commit", "変更を保存", "コミットして", or any request to record code changes.
---

# COMMIT

Safe git commit workflow with Conventional Commits format.

## Phase Overview

| # | Phase | Content | Stop |
|---|-------|---------|------|
| 1 | PRE-CHECK | Verify current branch ≠ main/master | |
| 2 | STATUS | git status + diff + log --oneline -10 (parallel) | |
| 3 | MESSAGE | Draft Conventional Commits message | |
| 4 | COMMIT | Stage specific files + commit via HEREDOC | |
| 5 | VERIFY | git status post-commit | |

For commit message format, staging rules, and prohibited actions, load `references/rules.md`.
