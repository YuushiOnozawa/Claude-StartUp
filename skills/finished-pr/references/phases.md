# FINISHED-PR — Phase Detail ref

## Phase 1: DETECT

Determine the current branch, PR number, and worktree status.

### Step 1: Detect branch

Check session context first, then fall back:

```bash
# Priority 1: $WORKTREE_PATH is in session context (set by /worktree new)
#   → BRANCH=$(git -C "$WORKTREE_PATH" branch --show-current)
#   → WORKTREE_ACTIVE=true

# Priority 2: git worktree list shows a path matching ./worktree/<branch>
git worktree list --porcelain
#   → parse "worktree ./worktree/..." entries (excluding the main worktree)
#   → if found: BRANCH=<branch>, WORKTREE_PATH=<path>, WORKTREE_ACTIVE=true

# Priority 3: current branch in main checkout
BRANCH=$(git branch --show-current)
WORKTREE_ACTIVE=false
```

If `BRANCH` is `main` or `master`: abort with error — "main/master ブランチは処理対象外です。対象ブランチに切り替えてから再実行してください。"

Hold: `$BRANCH`, `$WORKTREE_PATH` (if applicable), `$WORKTREE_ACTIVE`

### Step 2: Detect PR number

Use `gh pr view` with built-in `-q` (no jq dependency):

```bash
PR_NUM=$(gh pr view "$BRANCH" --json number -q '.number' 2>/dev/null)
PR_URL=$(gh pr view "$BRANCH" --json url    -q '.url'    2>/dev/null)
PR_TITLE=$(gh pr view "$BRANCH" --json title -q '.title'  2>/dev/null)
```

If `$PR_NUM` is empty (merged PR not found by branch name), try by list:
```bash
PR_NUM=$(gh pr list --head "$BRANCH" --state merged --json number -q '.[0].number' --limit 1 2>/dev/null)
```

If still empty: prompt user and validate before continuing:
```
PR が見つかりませんでした。PR 番号を手動で入力してください:
```
After user input: set `PR_NUM` to the entered value and confirm it is numeric before proceeding.

Hold: `$PR_NUM`, `$PR_URL`, `$PR_TITLE`

### Step 3: Extract related Issues

```bash
PR_BODY=$(gh pr view "$PR_NUM" --json body -q '.body')
# Extract: Closes/Fixes/Resolves #N (case-insensitive)
ISSUE_NUMS=$(echo "$PR_BODY" | grep -oiE '(closes|fixes|resolves)[[:space:]]+#[0-9]+' | grep -oE '[0-9]+')
```

Hold: `$ISSUE_NUMS` (space-separated list, may be empty)

### Step 4: Check remote branch existence

```bash
REMOTE_EXISTS=$(($(git ls-remote --heads origin "$BRANCH" | wc -l)))
# REMOTE_EXISTS=1 → remote branch exists; 0 → already deleted (by GitHub auto-delete)
# Arithmetic expansion $((n)) trims whitespace from wc -l output reliably
```

Hold: `$REMOTE_EXISTS`

---

## Phase 2: CONFIRM ✋

Present a summary and wait for user approval.

Format:
```
## 後処理確認 ✋

- **ブランチ**: $BRANCH
- **PR**: #$PR_NUM — $PR_TITLE
  $PR_URL
- **クローズする Issue**:
  [Issue が見つかった場合] #N, #M, ...
  [見つからなかった場合] (なし — 後で選択)
- **削除対象**:
  - ローカル: $BRANCH
  - リモート: origin/$BRANCH [またはリモートは既に削除済み]
  [WORKTREE_ACTIVE=true の場合]
  - worktree: $WORKTREE_PATH

1. 続行
2. キャンセル
```

**Issue が見つからなかった場合** (ISSUE_NUMS が空):
```
⚠️  PR がどの Issue も参照していませんでした。

1. Issue 番号を手動で指定する（例: 123 456）
2. Issue クローズをスキップする
3. キャンセル
```
Handle the response before proceeding.

On **キャンセル**: exit immediately.

---

## Phase 3: MAIN

```bash
git checkout main
git pull
```

On error: report and stop.

---

## Phase 4: ISSUE

For each issue number in `$ISSUE_NUMS` (or the user-specified list):

```bash
gh issue close "$ISSUE_NUM" --comment "PR #$PR_NUM のマージにより自動クローズ。"
```

Show: `✓ Issue #$ISSUE_NUM をクローズ`

If no issues (user chose to skip): show `- Issue クローズをスキップ`

---

## Phase 5: BRANCH

### Delete local branch

```bash
if git branch -d "$BRANCH" 2>/dev/null; then
  echo "✓ ローカルブランチ削除: $BRANCH"
elif git branch -D "$BRANCH"; then
  echo "✓ ローカルブランチ削除（強制）: $BRANCH"
else
  echo "⚠️  ローカルブランチ削除に失敗しました: $BRANCH（手動で削除してください）"
fi
```
# Note: -d is safe (merged check); -D is forced fallback for worktree-checked-out branches

### Delete remote branch (if exists)

```bash
if [ "$REMOTE_EXISTS" = "1" ]; then
  git push origin --delete "$BRANCH"
  echo "✓ リモートブランチ削除: origin/$BRANCH"
else
  echo "- リモートブランチは既に削除済み (skip)"
fi
```

---

## Phase 6: WORKTREE（WORKTREE_ACTIVE=true のみ）

```bash
if git worktree remove "$WORKTREE_PATH" 2>/dev/null; then
  git worktree prune 2>/dev/null || true
  WORKTREE_REMOVED=true
  echo "✓ worktree 削除: $WORKTREE_PATH"
else
  WORKTREE_REMOVED=false
  echo "⚠️  worktree の削除に失敗しました: $WORKTREE_PATH"
  echo "   手動で 'git worktree remove $WORKTREE_PATH && git worktree prune' を実行してください"
fi
```

---

## Phase 7: DONE

```
✅ 後処理完了

- main に切り替え済み・最新を取得
[Issue クローズした場合] - Issue #N をクローズ
- ブランチ $BRANCH を削除（ローカル + リモート）
[WORKTREE_REMOVED=true の場合]  - worktree $WORKTREE_PATH を削除
[WORKTREE_REMOVED=false の場合] - ⚠️ worktree は手動で削除が必要
```
