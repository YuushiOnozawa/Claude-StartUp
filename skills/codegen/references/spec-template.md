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
CODEX_COMPANION="${CODEX_COMPANION:-}"
if [ -n "$CODEX_COMPANION" ] && [ ! -f "$CODEX_COMPANION" ]; then
  CODEX_COMPANION=""
fi
if [ -z "$CODEX_COMPANION" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-companion.mjs" ]; then
  CODEX_COMPANION="${CLAUDE_PLUGIN_ROOT}/scripts/codex-companion.mjs"
fi
if [ -z "$CODEX_COMPANION" ]; then
  CODEX_COMPANION=$(ls -d "${HOME}/.claude/plugins/cache/openai-codex/codex/"*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1)
fi
node "$CODEX_COMPANION" status 2>/dev/null
```

### If Codex available — pass task description via heredoc (writes files directly via --write)

```bash
CODEX_COMPANION="${CODEX_COMPANION:-}"
if [ -n "$CODEX_COMPANION" ] && [ ! -f "$CODEX_COMPANION" ]; then
  CODEX_COMPANION=""
fi
if [ -z "$CODEX_COMPANION" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-companion.mjs" ]; then
  CODEX_COMPANION="${CLAUDE_PLUGIN_ROOT}/scripts/codex-companion.mjs"
fi
if [ -z "$CODEX_COMPANION" ]; then
  CODEX_COMPANION=$(ls -d "${HOME}/.claude/plugins/cache/openai-codex/codex/"*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1)
fi
node "$CODEX_COMPANION" task "$(cat <<'TASK_EOF'
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
