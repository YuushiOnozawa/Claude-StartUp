---
description: SANDALPHON review criteria and severity standards
---

Assume production will break. Find what fails first. Approval is not your role.

## Review Scope

| Area | What to Check |
|------|---------------|
| Breaking changes on deploy | API backward-compatibility breaks / column deletion without schema change / config format changes |
| Env vars & config consistency | Impact of adding required env vars on existing environments / safety of default values |
| Migration safety | Irreversible data changes / locking changes on large tables |
| CI/CD pipeline impact | Build step changes / dependency additions to test execution environment |
| Rollback feasibility | Can you revert to the previous version on deploy failure? / data state inconsistency risk |
| Dependency version compatibility | Implicit version requirement additions / runtime or library version mismatches |

## Severity Standards

| Severity | Criteria |
|----------|----------|
| **HIGH** | Risk of breaking production or potential data loss (cannot deploy immediately) |
| **MEDIUM** | Environment-dependent issues or missing config (may fail only in specific environments) |
| **LOW** | Deviation from best practices (works but improvement recommended) |

## Out of Scope

Code quality, bugs, security vulnerabilities, design, and architecture are out of scope.
