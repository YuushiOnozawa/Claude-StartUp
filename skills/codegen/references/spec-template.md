# Codegen — Spec Template & Commands

## SPEC Phase: Implementation Spec Format

Draft the spec in this structure before calling the local LLM:

```
## Implementation Spec

### Target File
<file path>

### Change Location
<code snippet with surrounding context (before)>

### Requirements
<bullet list — what to implement, concisely and specifically>

### Code Style
<indent style, naming convention, type hints, etc. extracted from the target file>

### Output Format
Output only the replacement code block. No explanations, no added comments, no code fences.
```

## GENERATE Phase: Commands

### Ollama availability check

```bash
ollama list 2>/dev/null | grep -q "gemma4:12b"
```

### If Ollama available — pipe spec via heredoc (no temp file)

```bash
cat << 'PROMPT_EOF' | ollama run gemma4:12b
<expand the spec drafted in SPEC phase here>
PROMPT_EOF
```

### If Ollama unavailable — Haiku fallback

Pass the spec to `Agent(subagent_type="general-purpose", model="haiku")` with instruction to output code only.

## APPLY Phase: Validation

Before applying, verify syntax:
- Python: `python -m py_compile <file>`
- Shell: `bash -n <file>`
- JS/TS: `node --check <file>` or `tsc --noEmit`

Apply with the Edit tool.
