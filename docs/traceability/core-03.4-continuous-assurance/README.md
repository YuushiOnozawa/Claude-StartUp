# Core 03.4: ドキュメント・CI・verify による継続保証が不足している

> 旧番号: core-06（2026-07-06 実行順に並べ替え）

## 核問題名

ドキュメント・CI・verify による継続保証が不足している

## 関連Fable項目

- 03: ドキュメント陳腐化
- 07: リポジトリ衛生
- 10: セットアップ統合検証 doctor / verify の追加
- 11: CI パイプラインの追加
- 12: セットアップ後の手動ステップ・チェックリスト整備

## 関連するリポジトリ目的

- 目的達成状況の確認
- 目的に対する要求・仕様・実装・テストの漏れ把握
- 開発フローSKILL
- 継続運用と再発防止

## 問題概要

実装とドキュメントのズレ、CI不在、verify不在、手動ステップ導線不足、未追跡ファイル滞留があり、整合性を継続的に保証する仕組みが不足している。

## 分類

必須

## confidence

high

## 人間確認が必要な点

- shellcheck厳格度
- smoke testでネットワーク・Ollama・pCloud依存をどこまで扱うか
- CI fail と verify warn の境界
- auditディレクトリを追跡対象にするか

## 外部移管受け入れ（2026-07-07）

core-02（live-deploy-drift）の Step 3 作業中に、以下が core-02 の範囲外として本 core-03.4 へ移管された:

- **worktree 残骸問題**: PR マージ後に worktree ブランチ・作業ファイルが残存する。`/finished-pr` への cleanup ステップ追加等が候補
- **.gitignore 整合**: 開発リポジトリ `~/srcs/Claude-StartUp` に未追跡の `.codex/`、`CLAUDE.local.md`、`docs/audit-2026-07-05/`、`scripts/index-investigations.sh` 等が存在。`.gitignore` への追加を検討

これらは「リポジトリ衛生（Fable 07）」の問題であり、core-02 が再定義した「還流経路の確立」とは独立した問題クラス。
本 core-03.4 の Step 3（requirements）で取り込み判断を行うこと。

- **派生元**: core-02 requirements.md（2026-07-07）+ sonnet-handoff-2026-07-07.md

## 重複・横断関係

Fable 03 は core-03.1、07 は core-02、10/12 は core-03.3、12 は core-01 と重複する。

## 注意

このフォルダは作業構造の再配置であり、要求・仕様・実装方針を確定するものではない。
## ステータス

| Document | Status | Notes |
|---|---|---|
| requirements.md | approved | 人間確認・承認済み（2026-07-07） |
| specification.md | draft | requirements 確定後に更新 |
| implementation-plan.md | draft | specification 確定後に更新 |
| test-plan.md | draft | specification 確定後に更新 |
| design-review.md | todo | Step 7 で作成 |
| traceability-map.md | draft | 各工程で更新 |
| traceability-audit.md | todo | Step 9 で作成 |
