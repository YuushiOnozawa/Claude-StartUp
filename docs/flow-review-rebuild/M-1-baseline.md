# Flow/Review 再構築 — M-1 baseline

- captured: 2026-09-08T05:35Z
- baseline SHA: 7e48394d224a5baa5d64b3972c85b75087ef8dc7
- branch: main

## 対象スキル (in-scope, 退避予定)

```
epic-flow              2 files      7105 bytes
dev-flow               2 files      9088 bytes
dev-flow-fast         13 files    165379 bytes
flow-common            5 files     92806 bytes
magi-hard              1 files     52307 bytes
magi-fast              1 files     10450 bytes
magi-common            7 files     59412 bytes
codex-hard             1 files      2947 bytes
codex-fast             1 files      2103 bytes
review-fast            1 files       408 bytes
review-hard            1 files       440 bytes
review-post            1 files       581 bytes
pr-review              1 files      5381 bytes
pr-review-respond      1 files     10228 bytes
melchior               3 files      3300 bytes
balthasar              3 files      4988 bytes
casper                 3 files      5371 bytes
metatron               3 files      4062 bytes
sandalphon             3 files      3791 bytes
leliel                 3 files      4239 bytes
```

## 対象スクリプト (scripts/ 内、review/flow closure)
```
codex-review-merge.sh              16148 bytes
magi-diff-filter.sh                  352 bytes
magi-ground-findings.sh            11251 bytes
magi-impact-context.sh              8934 bytes
magi-split-hunk.sh                  2188 bytes
review-adjudicate-findings.sh       6989 bytes
review-dedup-findings.sh            2292 bytes
review-dispatch-envelope.sh         4987 bytes
review-findings-artifact.sh         8637 bytes
```

## 関連テスト (baseline の合否は M2 mining 時に記録)
```
test-advisor-run.sh
test-casper-engine-contract.sh
test-codex-review-audit.sh
test-codex-review-merge.sh
test-function-calling.sh
test-knowledge-rag-local.sh
test-magi-diff-filter.sh
test-magi-format.sh
test-magi-ground-findings.sh
test-ollama-run-options.sh
test-review-adjudicate-findings.sh
test-review-dedup-findings.sh
test-review-dispatch-envelope.sh
test-review-dispatch-wiring.sh
test-review-findings-artifact.sh
test-review-post-contract.sh
```

## 注記
- `scripts/{magi,review,codex}-*.sh` は review closure の一部。M2b で archive 対象に含める。
- `docs/comparison-*`, `docs/magi-*`, `docs/core*` 等の設計メモは対象外（コードではない）。
