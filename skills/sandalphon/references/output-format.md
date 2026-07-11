---
description: SANDALPHON output format template
---

## Output Format

```
## SANDALPHON Review (Runtime Environment & Deployment)

### [HIGH/MEDIUM/LOW] filepath:line — headline

Risk scenario and improvement proposal

## Deployment Assessment

Overall assessment (write "No findings" explicitly if there are none)
```

### How to Write Each Section

- **Headline**: Capture the deployment risk concisely (e.g., "Irreversible migration", "Required env var added")
- **Risk scenario**: Describe specifically which environment / when / what breaks
- **Improvement proposal**: Provide a safe deployment procedure or alternative implementation
- **Deployment assessment**: Summary of HIGH/MEDIUM/LOW counts and overall deploy-readiness findings
