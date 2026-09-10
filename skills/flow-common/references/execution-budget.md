<!-- GENERATED FROM execution-budget.json — DO NOT EDIT -->

# Flow/Review 実行時間バジェット

| フェーズ | 分類 | magi | codex | 強制箇所 |
|---|---|---:|---:|---|
| `ollama_call_wall_clock` | hard | 900s | 900s | caller timeout and scripts/ollama-run.sh flock wait |
| `generation_total` | derived | 36000s | 4800s | derived.generation_total の式 |
| `diff_cap` | gate | — | — | skills/magi-hard/SKILL.md and skills/dev-flow-fast/references/codex-review-hard.md step 1 |
| `casper` | soft | 900s | 900s | skills/flow-common/references/casper-engine.md chunk boundary |
| `normalizer` | hard | 900s | 900s | skills/magi-common/references/normalizer.md caller timeout |
| `audit` | hard | 900s | — | skills/magi-common/references/codex-audit.md |
| `importance` | hard | 900s | — | skills/magi-common/references/codex-importance.md |
| `review_post` | mixed | 3120s | 3120s | skills/flow-common/references/review-post.md |
| `cleanup` | hard | 10s | 10s | managed run cleanup |

## 導出値

- magi `generation_total`: 36000s
- magi `max_configured_allowance`: `generation_total + casper + normalizer + audit + importance + review_post + cleanup` = 42730s
- codex `generation_total`: 4800s
- codex `max_configured_allowance`: `generation_total + casper + normalizer + audit + importance + review_post + cleanup` = 9730s

## Policy

- `auto_takeover`: `false`
- `auto_takeover_allowed_when`: `no soft/mixed/unbounded phase`
- soft、mixed、unbounded phase が1件でもあれば auto_takeover は必ず false。planned_overdue_at は run 固有値をこの JSON に保存せず、run 開始時に実際の chunk 数と persona 数から導出する。
