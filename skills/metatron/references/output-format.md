---
description: METATRON output format template
---

## Output Format

```
## METATRON Review (Security)

### [HIGH/MEDIUM/LOW] filepath:line — headline

Attack scenario and improvement proposal

## Security Assessment

Overall assessment (write "No findings" explicitly if there are none)
```

### How to Write Each Section

- **Headline**: Capture the essence of the problem concisely (e.g., "Command injection possible", "Hardcoded secret")
- **Attack scenario**: Describe specifically who / how / what can be attacked
- **Improvement proposal**: Provide the fix or a safer alternative
- **Security assessment**: Summary of HIGH/MEDIUM/LOW counts and overall security findings
