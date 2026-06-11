# Commit Rules

## Conventional Commits Format

```
<type>(<scope>): <日本語の説明>

<本文（任意、日本語）>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

**Types:** `feat` / `fix` / `docs` / `style` / `refactor` / `test` / `chore` / `perf` / `ci` / `build` / `revert`

- type / scope: English (immutable)
- subject / body: Japanese
- Focus on *why*, not *what*
- 1 commit = 1 concern; propose splitting if mixed
- Sensitive files (`.env`, credentials): warn and abort

## Staging

Never use `git add -A` or `git add .` — stage files individually.

Commit message via HEREDOC:

```bash
git commit -m "$(cat <<'EOF'
feat(scope): 日本語の説明

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

> CommitLint validation is delegated to the commit-msg hook. Do not run it manually.

## Prohibited

| Action | Exception |
|--------|-----------|
| Direct commit to `main` / `master` | — (always abort) |
| `--no-verify` | — |
| `--amend` | User explicitly requests |
| Force push to `main` / `master` | — |
| Auto-push after commit | User explicitly requests |
