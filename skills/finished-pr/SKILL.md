---
name: finished-pr
description: Post-PR merge cleanup skill. Use this skill EVERY TIME the user says "マージ完了", "merged", "/finished-pr", "PRがマージされた", "マージした", "merge complete", "after merge", "PRをマージしたので", or any indication that a PR has just been merged and they want to clean up. Automates: main checkout + pull, related Issue close, local/remote branch deletion, and worktree removal. Don't make the user do these cleanup steps manually — invoke this skill as soon as they say the PR was merged.
---

# FINISHED-PR

Post-merge cleanup workflow. Runs automatically after a PR is merged.

## Phase Overview

| # | Phase | Content | Stop |
|---|-------|---------|------|
| 1 | DETECT | ブランチ・PR番号・worktree 有無を特定 | |
| 2 | CONFIRM | 処理内容をユーザーに提示 | ✋ |
| 3 | MAIN | `git checkout main && git pull` | |
| 4 | ISSUE | 関連 Issue をクローズ | |
| 5 | BRANCH | ローカル・リモートブランチ削除 | |
| 6 | WORKTREE | worktree 削除（使用時のみ） | |
| 7 | DONE | 完了報告 | |

For full phase instructions with commands, load `references/phases.md`.
