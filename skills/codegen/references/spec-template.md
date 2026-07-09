# Codegen — Spec Template & Commands

## SPEC Phase: Task Description Format

Draft the task description in this structure before calling Codex:

```
## Task Description

### Target File
<file path>

### Requirements
<bullet list — what to implement, concisely and specifically>
```

## GENERATE Phase: Commands

`skills/flow-common/references/codex-task-runner.md` を Read し、以下の変数をセットしてランナー手順（ステップ 1〜5）に従う。

- `TASK_TMPDIR=$(mktemp -d)`
- `CODEX_TASK_MODE=repo-write`
- `WORKTREE_PATH=$WORKTREE_PATH`（worktree チェックアウトパス。dev-flow Phase 4 から呼ぶ場合は必ず設定すること）

**ステップ 4 の prompt 内容**（`$TASK_TMPDIR/task-prompt.txt` に書き込む）:
> ⚠ prompt 書き込み時は `$WORKTREE_PATH` / `$TASK_TMPDIR` を実パスに展開して埋め込むこと（quoted heredoc は変数を展開しないため）。

SPEC フェーズで作成したタスク記述をそのまま書き込む。

**`CODEX_TASK_SKIPPED` 時（フォールバック）:** 以下の Haiku フォールバック手順を実行する。

### If Codex unavailable — Haiku fallback

Pass the task description to `Agent(subagent_type="general-purpose", model="haiku")` with instruction to output code only.
Before applying, verify syntax:
- Python: `python -m py_compile <file>`
- Shell: `bash -n <file>`
- JS/TS: `node --check <file>` or `tsc --noEmit`

Apply with the Edit tool.
