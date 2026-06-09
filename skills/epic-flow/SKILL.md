---
name: epic-flow
description: This skill should be used when the user expresses intent to build or implement something. It automatically assesses requirement scale: routes to /dev-flow for single-feature work (one PR), or decomposes into GitHub Issues and runs a feature loop for multi-feature epics (multiple PRs). Trigger on "/epic-flow", "epic-flow", "〜を作りたい", "〜を実装したい", "〜機能を追加したい", "〜を追加して", "〜を作って".
---

# EPIC-FLOW

Scale-aware development workflow that routes to the appropriate workflow automatically.

## Phase 0: SCALE ASSESSMENT

Assess the user's requirements using these criteria:

| Scale | Primary criterion | Secondary | Routing |
|-------|------------------|-----------|---------|
| **DEV** | Completable in a single independent PR | 1–3 affected files | Delegate to `/dev-flow` |
| **EPIC** | Multiple independent PRs expected | 4+ affected files | Continue to EPIC phases |

**On ambiguity:** Ask in one sentence ("単一機能として進めますか、機能分解しますか？")

### DEV route

Execute `/dev-flow` as-is. Do not proceed to EPIC phases.

### EPIC route

Proceed to Phase 1.

For full phase instructions with commands and templates, load `references/phases.md`.
