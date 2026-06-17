# MAGI Output Format

Output ONLY in the format below.
The review header and assessment header are defined in `task-instruction.md` for each persona.

## Output Format

```
## {Review Header defined in task-instruction.md}

### [HIGH] filepath:line — short headline
Description and improvement proposal.

### [MEDIUM] filepath:line — short headline
Description and improvement proposal.

### [LOW] filepath:line — short headline
Description and improvement proposal.

## {Assessment Header defined in task-instruction.md}
[1–2 sentence overall evaluation. Write "No findings" explicitly if there are none.]
```

## Notes

- Use `### [HIGH]`, `### [MEDIUM]`, `### [LOW]` as **separate entries** — NEVER combine as `[HIGH/MEDIUM/LOW]`
- Every finding must include a specific reason explaining why it is a problem
- Write "No findings" explicitly if there are none (do not omit)
