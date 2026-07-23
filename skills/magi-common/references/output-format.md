# MAGI Output Format

CRITICAL: Output ONLY the following format. No summaries, no explanations, no descriptions of what the code does.

The review header and assessment header are defined in `task-instruction.md` for each persona.

## Output Format

## {Review Header defined in task-instruction.md}

### [HIGH] filepath:line — short headline
Description and improvement proposal.

### [MEDIUM] filepath:line — short headline
Description and improvement proposal.

### [LOW] filepath:line — short headline
Description and improvement proposal.

## {Assessment Header defined in task-instruction.md}
[1–2 sentence overall evaluation. If there are zero findings, include "No findings" explicitly in this Assessment section.]

## Notes

- Use `### [HIGH]`, `### [MEDIUM]`, `### [LOW]` as **separate entries** — NEVER combine as `[HIGH/MEDIUM/LOW]`
- Every finding must include a specific reason explaining why it is a problem
- The `line` in `filepath:line` must be a single positive integer only; ranges (`49-61`) and multiple line numbers (`49, 53`) are forbidden. For a range, write only its first line.
- Write `No findings` explicitly only when there are zero findings; if any finding exists, never write `No findings`.
- If there are zero findings, include `No findings` within the persona-specific Assessment section (`## ... Assessment` or `## Compliance Status`).
- In a diff, a matching `-` line and `+` line form one change, not duplicate code. Do not report similar deletion/addition lines as a duplicate.
- Do not output generic control templates or placeholder control lines.

## Finding Limits (mandatory)

- Report at most 8 findings per chunk. If you find more, keep only the 8 most severe.
- Consolidate repeated instances of the same pattern into ONE finding; mention "multiple occurrences" in the body instead of repeating the finding.
- Never output two findings with the same headline.
