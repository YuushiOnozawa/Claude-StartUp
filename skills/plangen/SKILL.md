---
name: plangen
desc: Delegate plan generation to Codex Plugin (Sol / gpt-5.6-sol) for higher-quality
  implementation plans. Claude curates context; Codex drafts the plan; Claude reviews and
  adopts it into the active plan file. Read-only — Sol never writes files.
  Trigger: "/plangen", "plangenで計画", "Solでプラン作成"
argument-hint: "<what needs to be planned>"
---

# PLANGEN

Cost-efficient plan generation: Claude curates context, Codex (Sol) drafts the plan, and
Claude reviews and adopts it when appropriate.
Falls back to Luna and then Haiku when the preceding engine is unavailable or produces an
invalid draft.

## Phase Overview

| # | Phase | Content |
|---|-------|---------|
| 1 | ORIENT | Read target files, existing implementation, constraints, and related Issues |
| 2 | CONTEXT | Organize the planning context to pass to Sol: background, constraints, scope, and expected output |
| 3 | GENERATE | Run `codex-companion.mjs task --model gpt-5.6-sol` without `--write` so Sol drafts the plan; see `references/spec-template.md` |
| 4 | ADOPT | Claude validates the draft and adopts it into the active plan file only in Plan Mode; outside Plan Mode, present it as a draft without writing any file |

For the Planning Brief format, prompt isolation, availability check, and generation commands,
see `references/spec-template.md`.

## Read-only contract

Always omit `--write`; never attach it to any Codex invocation. Sol must not edit files, run
commands, or communicate externally. These are prompt-level instructions, not restrictions
enforced at runtime. The enforceable guarantee is limited to omitting `--write`, so the Codex
companion sandbox does not permit workspace file changes. Its output is only a draft, and
Claude is responsible for validation and adoption.

The same prompt-level read-only instruction applies to Luna and Haiku fallbacks: they should
produce a plan draft only and should not edit files, execute commands, or make external
communications. Omitting `--write` provides the same workspace-write protection for Codex
fallbacks; Haiku has no corresponding runtime enforcement.

## Fallback and report contract

Try each stage at most once, in this order, with the model explicitly specified:

1. `--model gpt-5.6-sol` (Sol)
2. `--model gpt-5.6-luna` (Luna)
3. `Agent(subagent_type="general-purpose", model="haiku")` (Haiku)

Cascade only when the current stage has a non-zero exit, empty stdout, obvious model-error
wording, or output that lacks the minimum plan structure of headings plus implementation-like
content. Stop as soon as a valid draft is available; do not rely on the CLI default model.

The REPORT must state which engine/model produced the adopted or presented draft: Sol /
`gpt-5.6-sol`, Luna / `gpt-5.6-luna`, or Haiku / `haiku`.

In Plan Mode, Claude must validate the draft against the curated context and then reflect the
accepted content in the plan file whose path is present in context. Outside Plan Mode, Claude
must not write any file and must present the valid draft as-is for the user to adopt.
