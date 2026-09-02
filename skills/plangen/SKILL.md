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
| 3 | GENERATE | Run the `run_in_background` Bash block without `--write` so Sol drafts the plan; see `references/spec-template.md` |
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

Cascade only when the current stage has a non-zero exit, empty stdout, or output that lacks the
minimum plan structure of headings plus implementation-like content. Do not use model-error
wording as a cascade condition. Stop as soon as a valid draft is available; do not rely on the
CLI default model.

Each Codex stage runs as a background job and is polled for at most 900 seconds from launch, with
an `OVERALL=2400` seconds cascade guard checked before each stage. A deadline or hang causes one
`cancel` request for the preceding job; a launch failure also prevents starting Luna when the job
ID is unavailable. If cancel was issued for a stage, the next stage is Haiku rather than Luna;
Luna runs only when the preceding stage reaches terminal without cancel being issued.
The 900 seconds / `OVERALL=2400` values are approximate upper bounds that include the 15-second
polling interval and up to 60-second `status` RPC timeout, not exact cutoff times; terminal results
(including `completed`) observed after the deadline are adopted as-is.

GENERATE runs in a Bash block with `run_in_background`; after it exits, the harness invokes Claude
again. If the block output has no `REPORT:` line, treat it as `CODEX_FAILURE` and use Haiku. At
startup, the block reads its previous marker file and cancels residual jobs before launching Sol.

The REPORT must state which engine/model produced the adopted or presented draft: Sol /
`gpt-5.6-sol`, Luna / `gpt-5.6-luna`, or Haiku / `haiku`.

`_plangen_output_ok` (and the equivalent Haiku check) verifies only minimum structural validity:
non-empty output with a heading and implementation-like content. Whether the draft is actually
a useful plan, including whether it is a refusal or error message, is a content-quality check
that Claude must always perform during ADOPT. This separation is intentional; do not restore
wording-based content validation to GENERATE, since normal plan headings such as `# Error
handling` can trigger false cascades.

In Plan Mode, Claude must validate the draft against the curated context and then reflect the
accepted content in the plan file whose path is present in context. Outside Plan Mode, Claude
must not write any file and must present the valid draft as-is for the user to adopt.
