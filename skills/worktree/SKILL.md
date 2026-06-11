---
name: worktree
desc: Manage git worktrees for isolated parallel development. Subcommands: new <branch>, done <branch>, list. Trigger: "/worktree", "worktree new", "worktree done", "worktree list".
---

# WORKTREE

Git worktree lifecycle manager. All worktrees are created under `./worktree/` inside the current repo.

## Subcommands

### new \<branch\>

```bash
BRANCH="$1"
WORKTREE_PATH="./worktree/${BRANCH}"
mkdir -p ./worktree
git worktree add "$WORKTREE_PATH" -b "$BRANCH"
```

Output `$WORKTREE_PATH` so the caller can hold it (e.g., `$WORKTREE_PATH = ./worktree/feat-xxx`).

Present:
```
✓ Worktree 作成: $WORKTREE_PATH（ブランチ: $BRANCH）
  Phase 4 以降のファイル操作はこのパスを基点にしてください。
```

### done \<branch\>

```bash
BRANCH="$1"
WORKTREE_PATH="./worktree/${BRANCH}"
git worktree remove "$WORKTREE_PATH"
git branch -d "$BRANCH"
```

Present: `✓ Worktree 削除: $WORKTREE_PATH`

### list

```bash
git worktree list
```
