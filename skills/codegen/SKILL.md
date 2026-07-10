---
name: codegen
desc: Delegate code gen to Codex Plugin (GPT-5.4). Claude writes the task description; Codex implements and writes files directly — reducing Claude output-token cost. Trigger: "/codegen", "codegenで実装", "Codexで実装"
argument-hint: "<what to implement>"
---

# CODEGEN

Cost-efficient code gen: Claude plans, Codex (GPT-5.4) implements.
Falls back to Haiku when Codex is unavailable.

## Phase Overview

| # | Phase | Content |
|---|-------|---------|
| 1 | ORIENT | Read target files; extract style, naming, patterns |
| 2 | SPEC | Draft task description for Codex |
| 3 | GENERATE | Run Codex via `codex-companion.mjs` — writes files directly (or Haiku fallback) |
| 4 | REPORT | State which path was used (Codex / Haiku fallback) |

## Mode: tdd (`/codegen tdd`)
テストファイル先行生成（Red 確認まで）。実装コード・fixture・helper は生成しない。
詳細は `references/spec-template.md` の「TDD Mode」セクションを参照。

For spec format and generate commands, see `references/spec-template.md`.
