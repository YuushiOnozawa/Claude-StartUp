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

### Codex availability check

```bash
node "${HOME}/.claude/plugins/cache/openai-codex/codex/1.0.5/scripts/codex-companion.mjs" status 2>/dev/null
```

### If Codex available — pass task description via heredoc (writes files directly via --write)

```bash
node "${HOME}/.claude/plugins/cache/openai-codex/codex/1.0.5/scripts/codex-companion.mjs" task "$(cat <<'TASK_EOF'
<expand the task description drafted in SPEC phase here>
TASK_EOF
)" --write
```

### If Codex unavailable — Haiku fallback

Pass the task description to `Agent(subagent_type="general-purpose", model="haiku")` with instruction to output code only.
Before applying, verify syntax:
- Python: `python -m py_compile <file>`
- Shell: `bash -n <file>`
- JS/TS: `node --check <file>` or `tsc --noEmit`

Apply with the Edit tool.
