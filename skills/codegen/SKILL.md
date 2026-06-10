---
name: codegen
desc: Delegate code generation to a local LLM (gemma4:12b). Claude writes the implementation spec; the local LLM writes the code — reducing Claude output-token cost. Trigger: "/codegen", "codegenで実装", "ローカルLLMで実装"
argument-hint: "<what to implement>"
---

# CODEGEN

Cost-efficient code generation: Claude plans, gemma4:12b implements.
Falls back to Haiku when Ollama is unavailable.

## Phase Overview

| # | Phase | Content |
|---|-------|---------|
| 1 | ORIENT | Read target files; extract style, naming, patterns |
| 2 | SPEC | Draft detailed implementation spec |
| 3 | GENERATE | Run `gemma4:12b` via Ollama (or Haiku fallback) |
| 4 | APPLY | Edit target files with generated code; verify syntax |
| 5 | REPORT | State which path was used (Ollama / Haiku fallback) |

For spec format and generate commands, see `references/spec-template.md`.
