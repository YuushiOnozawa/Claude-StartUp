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

# Validate branch name (alphanumeric, hyphen, slash, underscore only)
if ! echo "$BRANCH" | grep -qE '^[a-zA-Z0-9/_-]+$'; then
  echo "ERROR: Invalid branch name: $BRANCH (use alphanumeric, /, -, _ only)"
  exit 1
fi

WORKTREE_PATH="./worktree/${BRANCH}"
mkdir -p ./worktree
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  git worktree add "$WORKTREE_PATH" "$BRANCH"
else
  git worktree add "$WORKTREE_PATH" -b "$BRANCH"
fi
```

Present: `✓ Worktree 作成: $WORKTREE_PATH（ブランチ: $BRANCH）`

Return `$WORKTREE_PATH` to the caller.

### done \<branch\>

```bash
BRANCH="$1"
WORKTREE_PATH="./worktree/${BRANCH}"

git worktree remove "$WORKTREE_PATH" || {
  echo "ERROR: Failed to remove worktree at $WORKTREE_PATH"
  echo "Hint: run 'git worktree prune' manually if the directory was already deleted"
  exit 1
}
git worktree prune
git branch -d "$BRANCH"
```

Present: `✓ Worktree 削除: $WORKTREE_PATH`

### list

```bash
git worktree list
```
