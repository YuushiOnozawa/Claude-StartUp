---
name: traceability-board-update
description: 全体ボード更新。各 core-XX/README.md のステータス表を集約して docs/traceability/README.md を再生成する。Trigger: "/traceability-board-update", "ボード更新", "トレサビボード"
argument-hint: ""
---

# TRACEABILITY-BOARD-UPDATE（全体ボード更新）

各 `traceability-*` スキルの完了時に呼ばれるほか、単独でも実行できる（ボードの整合回復用）。

## 手順

1. `skills/traceability-common/references/rules.md`（repo 内。なければ `~/.claude/skills/traceability-common/references/rules.md`） を Read する
2. `docs/traceability/core-*/README.md` を全件 Read し、各ステータス表を集約する
   （**ボードは各 core README からの派生物**。手で書かず必ず集約で再生成する）
3. `docs/traceability/README.md` を以下の構成で上書きする:

   ```markdown
   # トレーサビリティ全体ボード
   最終更新: YYYY-MM-DD（更新スキル名）

   | 核問題 | 分類 | req | spec | impl-plan | 実装 | design-review | test | audit |
   |---|---|---|---|---|---|---|---|---|
   | [core-01-...](core-01-.../README.md) | 必須 | draft | draft | ... |

   ## 次のアクション候補
   - core-XX: <前工程 approved 済みで次に進める Step>
   ## blocked
   - core-XX: <理由>
   ```

4. core README とボードの食い違いを検出した場合は core README を正として直し、差分を報告する

## 完了条件

- 全 core が 1 行ずつ載っており、各セルが core README のステータス表と一致する
- 次のアクション候補と blocked が現状を反映している
