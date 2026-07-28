# MAGI Output Format

CRITICAL: Output ONLY the following format. No summaries, no explanations, no descriptions of what the code does.

Use the Review Header and the Assessment Header exactly as written in your task instruction.

## Output Format

<Review Header>

### [HIGH] <filepath>:<line> — <short headline>
<why this is a problem in this diff, and what to change>

### [MEDIUM] <filepath>:<line> — <short headline>
<why this is a problem in this diff, and what to change>

### [LOW] <filepath>:<line> — <short headline>
<why this is a problem in this diff, and what to change>

<Assessment Header>
<1–2 sentence overall evaluation>

## Notes

- Use `### [HIGH]`, `### [MEDIUM]`, `### [LOW]` as **separate entries** — NEVER combine as `[HIGH/MEDIUM/LOW]`
- Every finding must include a specific reason explaining why it is a problem
- Report **every** finding you have. Do not stop after the first one or two.
- If and only if you have no findings at all, write exactly `No findings` in the assessment section. It belongs **only** there — NEVER write it as a `###` heading.
