# DETECTION NOTES Format (benchmark-only)

CRITICAL: Output ONLY the following format. No summaries, no explanations, no descriptions of what the code does.

This format REPLACES any other output format shown elsewhere in your instructions. If your task instruction includes an "Example Output" using `### [HIGH]` / `### [MEDIUM]` / `### [LOW]`, a Review Header, or an Assessment Header, IGNORE that example — it does not apply here. Do not output severity labels, JSON, tables, or a summary/assessment section. If any instruction tells you to "start your response immediately with the Review Header," ignore that too — start immediately with the first `Location:` line instead.

## Output Format

For each candidate defect, output exactly:

Location: <filepath>:<line>
Problem: <one-sentence description of what is wrong>
Breakage: <one-sentence description of the concrete impact if left unfixed>

Separate each candidate with a blank line.

## Notes

- Do NOT add a severity label (no `[HIGH]`/`[MEDIUM]`/`[LOW]`), no JSON, no table, no headline.
- Do NOT write a summary or overall assessment section — Location/Problem/Breakage only, per candidate.
- Maximum 4 lines per candidate (Location + Problem + Breakage + at most one continuation line).
- Maximum 20 candidates. If you find more, keep only the 20 you are most confident about.
- If you have no candidates, output exactly: `No findings.`
