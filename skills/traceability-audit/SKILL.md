---
name: traceability-audit
description: Step 9 トレーサビリティ監査。問題→要求→仕様→実装→テストの対応を全数確認し、漏れ・orphan・不整合を traceability-audit.md にまとめる。Trigger: "/traceability-audit", "core-XX を監査", "トレーサビリティ監査"
argument-hint: "<core-XX または all>"
---

# TRACEABILITY-AUDIT（Step 9: トレーサビリティ監査）

網羅性は「機械的チェック + Codex 二次確認」で担保するため、メインセッションは Sonnet の
ままでよい（モデル切替による 5h ウィンドウ消費を避ける）。Codex はクォータ消費ゼロ。

## 手順

1. `skills/traceability-common/references/rules.md`（repo 内。なければ `~/.claude/skills/traceability-common/references/rules.md`） を Read し、対象 core-XX を特定する
   （`all` なら全 core を順次監査）
2. **機械的チェック（表突合）**: 対象 core の全ドキュメント + `traceability-map.md` を Read し、
   **map ではなく実体を正**として突合する:
   - PROB → REQ / REQ → SPEC / SPEC → IMPL / SPEC → TEST で「派生先が無い」を検出（漏れ）
   - 逆方向で「派生元が無い」を検出: orphan implementation / orphan test / 根拠の無い map 行
   - IMPL の実装参照（PR/コミット）の実在、TEST の結果記録の有無を確認
3. **意味的チェック**: 対応があるものについて「SPEC は REQ を本当に実現しているか」
   「TEST は SPEC を本当に検証しているか」を確認し、疑わしいものを指摘候補に挙げる。
   **偽陰性を避ける方向**に倒す（見逃しより誤検知を許容）
4. **Codex 二次確認（クォータゼロ）**: 検出した指摘に `A-001` 形式の ID を付け、
   `skills/magi-common/references/codex-audit.md`（repo 内。なければ `~/.claude/skills/magi-common/references/codex-audit.md`） の手順で valid / false_positive / needs_human を
   判定させる。Codex 不可時はスキップし、その旨を監査文書に記録して全件を人間確認に回す
5. `traceability-audit.md` を作成する:
   漏れ / 不整合 / 過剰実装 / orphan implementation / orphan test / 未確認事項 /
   Codex 判定列 / 最終判定（verified 可否と条件）
6. map の誤り・欠落があれば修正する（根拠を添えて）
7. 3点セット更新（README ステータス表 / 全体ボード / map）
8. 人間確認: 各指摘に「誤検知 / 要対応 / 対象外」を付けてもらう AskUserQuestion（multiSelect 可）。
   要対応ゼロなら README ステータスを verified に更新してよいか確認する

## 完了条件

- 全 REQ に対応 SPEC、全 SPEC に対応 IMPL/TEST または未対応理由がある
- 指摘に Codex 判定（または未実施の記録）が付いている
- orphan・不明点が不明点として残っている（根拠のない対応関係を作っていない）
