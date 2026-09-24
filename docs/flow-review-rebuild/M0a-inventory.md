# Flow/Review 再構築 — M0a inventory

- captured: 2026-09-11
- SHA: 070aec4c5dfc5f5a444716f67b8970676df9bbfa（main、PR#420 マージ後）
- M-1 baseline (7e48394) からの差分: Issue#411 (PR-1/PR-2/PR-3) が反映済み

## repo 側 vs `~/.claude/skills/` 側（本セッションで一度フルsync実施済み）

```
                        repo              ~/.claude/skills/
epic-flow              2 files   7105B    2 files   7105B   一致
dev-flow               2 files   9088B    2 files   9088B   一致
dev-flow-fast         13 files 171934B   13 files 171934B   一致
flow-common            9 files 160342B    9 files 160342B   一致
magi-hard              1 files  61674B    2 files  82806B   ★drift（backup混入）
magi-fast              1 files  10450B    1 files  10450B   一致
magi-common            7 files  65008B    7 files  65008B   一致
codex-hard             1 files   3544B    1 files   3544B   一致
codex-fast             1 files   2136B    1 files   2136B   一致
review-fast            1 files    408B    1 files    408B   一致
review-hard            1 files    440B    1 files    440B   一致
review-post            1 files    581B    1 files    581B   一致
pr-review              1 files   5381B    1 files   5381B   一致
pr-review-respond      1 files  10228B    1 files  10228B   一致
melchior               3 files   3300B    3 files   3300B   一致
balthasar              3 files   4988B    3 files   4988B   一致
casper                 3 files   5371B    3 files   5371B   一致
metatron               3 files   4062B    4 files  18290B   ★drift（backup混入）
sandalphon             3 files   3791B    3 files   3791B   一致
leliel                 3 files   4239B    3 files   4239B   一致
```

★drift の内訳（両方とも同一原因）:
- `skills/magi-hard/SKILL.md.backup-pre-362-20260728-221437`
- `skills/metatron/SKILL.md.backup-pre-362-20260728-221437`

Issue #357（METATRON Codex化、2026-07-28）作業時の手動バックアップの残骸。`SKILL.md` という名前ではないため
Claude Code のスキル探索には引っかからない（=旧 entrypoint として active 解決されるリスクはない）。実害なし、
単なるゴミファイル。M2b の物理退避時に一緒に掃除する（今すぐ消す必要はない）。

## repo 側にあり `~/.claude/skills/` に一致確認済みの review/flow closure スクリプト

```
codex-review-merge.sh            16148B  deployed・一致
magi-diff-filter.sh                352B  deployed・一致
magi-ground-findings.sh          11251B  deployed・一致
magi-impact-context.sh            8934B  deployed・一致
magi-split-hunk.sh                2188B  deployed・一致
review-adjudicate-findings.sh     6989B  deployed・一致
review-dedup-findings.sh          2292B  deployed・一致
review-dispatch-envelope.sh       5051B  deployed・一致
review-findings-artifact.sh       8637B  deployed・一致
```

## M-1 baseline (7e48394) 以降の新規追加（Issue#411 由来、M2 fixture化の対象）

```
review-singleflight.sh           39774B  新規
review-dispatch-state.sh          8197B  新規
check-review-fast-no-post.sh      5052B  新規
codex-broker-run.sh               2687B  新規（PR-2）
skills/flow-common/execution-budget.json  7300B  新規（PR-1）
skills/flow-common/execution-budget.sh    4024B  新規（PR-1）
skills/flow-common/references/review-dispatch.md  新規
skills/flow-common/references/review-post.md      新規
skills/dev-flow-fast/references/codex-review-hard.md  新規
```

## `~/.claude/skills/` に存在し repo `skills/` に存在しないディレクトリ

```
lean-ctx  — Flow/Review スコープ外（lean-ctx MCP ツール、ユーザーのグローバル設定由来）
```

対象範囲（epic-flow/dev-flow/dev-flow-fast/flow-common/magi-*/codex-*/review-*/pr-review*/6ペルソナ）に
repo に存在しない孤立ディレクトリはゼロ。＝過去に repo から削除されたのに配備側だけ残っている旧スキルはない。

## 結論

- 現時点で「旧entrypointが意図せずactiveに解決される」リスクは実質ゼロ（backup 2ファイルはSKILL.md名ではないため無害）
- repo↔`~/.claude/` の乖離は今回のフルsync（skills/・scripts/ 全体）で解消済み

## 旧スキル無効化（実施済み、2026-09-11）

D3（production並走は置かない）通り、ユーザー確認（AskUserQuestion）の上で対象20スキルを
`~/.claude/skills/` から削除した。repo側（`skills/`）は無変更（`git status`で確認済み）。
物理退避（`archive/flow-review-v0/`への移動、`SKILL.md`→`SKILL.md.frozen`改名）はM2bで実施する。

削除対象（全て削除確認済み）:
```
epic-flow, dev-flow, dev-flow-fast, flow-common,
magi-hard, magi-fast, magi-common, codex-hard, codex-fast,
review-fast, review-hard, review-post, pr-review, pr-review-respond,
melchior, balthasar, casper, metatron, sandalphon, leliel
```

**影響**: 新Review/Flow（M9で完成予定）が揃うまで、`/magi-hard` `/codex-hard` `/dev-flow` `/dev-flow-fast`
`/review-hard` `/review-fast` `/review-post` `/pr-review` 等は本セッション環境で一切使用不可。
`/grill-me` `/codegen` `/commit` `/worktree` `/finished-pr` は対象外のため引き続き使用可能。

## M0a ゲート判定

旧スキルが active に解決されない: ✅ 達成（`~/.claude/skills/`から対象20件削除済み、孤立ディレクトリなし）
**M0a 完了**。次は M1（Issue#411/#414-416の凍結、圏内Issue棚卸しと非目標確定）。
