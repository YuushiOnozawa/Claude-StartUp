---
name: traceability-requirements
description: Step 3 要求定義。核問題の目的・問題から要求・受け入れ条件候補・対象外を定義し requirements.md を更新する。Trigger: "/traceability-requirements", "要求定義して", "core-XX の要求"
argument-hint: "<core-XX>"
---

# TRACEABILITY-REQUIREMENTS（Step 3: 要求定義）

## 手順

1. `skills/traceability-common/references/rules.md`（repo 内。なければ `~/.claude/skills/traceability-common/references/rules.md`） を Read し、対象 core-XX を特定する
2. 対象の `README.md`（問題概要・関連目的）と分類ドキュメントの該当詳細を Read する
3. `requirements.md` を更新する:
   - **問題**（何が問題か）と**要求**（何を満たすべきか）を分けて書く。REQ-XX-NN 付与
   - 各要求を関連目的に紐づける（紐づかない要求は書かない）
   - 受け入れ条件候補（検証可能な形）/ 対象外候補 / 人間確認事項
   - 実装方針に寄った記述は避ける（手段は Step 4 以降）
4. `traceability-map.md` に PROB → REQ の対応を追加する
5. 3点セット更新（README ステータス表 / 全体ボード / map）
6. 人間確認ポイントを提示して AskUserQuestion:
   要求が目的に対応しているか / 実装方針に寄りすぎていないか / 対象外が妥当か
   →「approved にする / draft のまま / 修正指示」

## 完了条件

- 問題と要求が混ざっていない。全要求が目的・PROB に紐づく
- 受け入れ条件候補・対象外・人間確認事項がある
- map に PROB → REQ が追加されている
