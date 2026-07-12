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
[1–2 sentence overall evaluation. Write "No findings" explicitly if there are none.]

## Notes

- Use `### [HIGH]`, `### [MEDIUM]`, `### [LOW]` as **separate entries** — NEVER combine as `[HIGH/MEDIUM/LOW]`
- Every finding must include a specific reason explaining why it is a problem
- Write "No findings" explicitly if there are none (do not omit)
- Sink mode only: when the prompt supplies a concrete completion marker, it must be the final non-empty line and must exactly match the supplied lowercase persona and four-digit chunk ID
- Sink mode only: a successful zero-findings result requires both an explicit "No findings" in the Assessment and the matching completion marker
- Legacy mode: no concrete completion marker is supplied; do not output a MAGI completion marker or the placeholder below

Sink mode template only (replace both placeholders with the concrete values supplied in the prompt):

<!-- MAGI_COMPLETE persona=<persona> chunk=<4桁ID> -->
