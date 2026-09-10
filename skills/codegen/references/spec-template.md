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
CODEX_BROKER_RUN=""
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -r "${CLAUDE_PLUGIN_ROOT}/scripts/codex-broker-run.sh" ]]; then
  CODEX_BROKER_RUN="${CLAUDE_PLUGIN_ROOT}/scripts/codex-broker-run.sh"
else
  CODEX_DISTRIBUTION_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$CODEX_DISTRIBUTION_ROOT" && -r "$CODEX_DISTRIBUTION_ROOT/skills/flow-common/execution-budget.json" \
    && -r "$CODEX_DISTRIBUTION_ROOT/scripts/codex-broker-run.sh" ]]; then
    CODEX_BROKER_RUN="$CODEX_DISTRIBUTION_ROOT/scripts/codex-broker-run.sh"
  else
    CODEX_BROKER_RUN="$HOME/.claude/scripts/codex-broker-run.sh"
  fi
fi
bash "$CODEX_BROKER_RUN" --check 2>/dev/null
```

### If Codex available — pass task description via heredoc (writes files directly via --write)

```bash
CODEX_BROKER_RUN=""
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -r "${CLAUDE_PLUGIN_ROOT}/scripts/codex-broker-run.sh" ]]; then
  CODEX_BROKER_RUN="${CLAUDE_PLUGIN_ROOT}/scripts/codex-broker-run.sh"
else
  CODEX_DISTRIBUTION_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$CODEX_DISTRIBUTION_ROOT" && -r "$CODEX_DISTRIBUTION_ROOT/skills/flow-common/execution-budget.json" \
    && -r "$CODEX_DISTRIBUTION_ROOT/scripts/codex-broker-run.sh" ]]; then
    CODEX_BROKER_RUN="$CODEX_DISTRIBUTION_ROOT/scripts/codex-broker-run.sh"
  else
    CODEX_BROKER_RUN="$HOME/.claude/scripts/codex-broker-run.sh"
  fi
fi
CODEGEN_PROMPT_FILE="$(mktemp)"
trap 'rm -f -- "$CODEGEN_PROMPT_FILE"' EXIT
cat > "$CODEGEN_PROMPT_FILE" <<'TASK_EOF'
<expand the task description drafted in SPEC phase here>
TASK_EOF
bash "$CODEX_BROKER_RUN" task --prompt-file "$CODEGEN_PROMPT_FILE" --write
```

### If Codex unavailable — Haiku fallback

Pass the task description to `Agent(subagent_type="general-purpose", model="haiku")` with instruction to output code only.
Before applying, verify syntax:
- Python: `python -m py_compile <file>`
- Shell: `bash -n <file>`
- JS/TS: `node --check <file>` or `tsc --noEmit`

Apply with the Edit tool.
