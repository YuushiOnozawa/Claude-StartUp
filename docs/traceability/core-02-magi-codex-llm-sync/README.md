# Core 02: MAGI / Codex / ローカルLLM連携の実体・参照・モデル割当がズレている

## 核問題名

MAGI / Codex / ローカルLLM連携の実体・参照・モデル割当がズレている

## 関連Fable項目

- 01: MAGI エージェント定義の参照不整合
- 02: setup/800-ollama-models.sh とスキルのモデル割当不整合
- 03: SKILLS.md / DESIGN.md / README.md のドキュメント陳腐化
- 06: スキル内スクリプト参照のパス解決不統一
- 08: Codex CLI の自動インストール不足

## 関連するリポジトリ目的

- 開発フローSKILL
- 1スキル1ローカルLLM
- Codex実装・Claudeオーケストラ
- MAGIレビューによる品質保証

## 問題概要

MAGI、ローカルLLM、Codex の実体が、参照パス、モデル割当、ドキュメント、setup で同期していない。開発フローのレビューゲートが期待通り動くかに直結する。

## 分類

必須

## confidence

high

## 人間確認が必要な点

- #203 の方針を完遂して references に一本化するか agents を復元するか
- METATRON の devstral を継続するか
- Codex CLI / plugin の確認済みバージョンをどこまで固定するか

## 重複・横断関係

Fable 02 は core-01、03 は core-06、08 は core-01 と重複する。

## 注意

このフォルダは作業構造の再配置であり、要求・仕様・実装方針を確定するものではない。
## ステータス

| Document | Status | Notes |
|---|---|---|
| requirements.md | draft | 人間確認前 |
| specification.md | draft | requirements 確定後に更新 |
| implementation-plan.md | draft | specification 確定後に更新 |
| test-plan.md | draft | specification 確定後に更新 |
| design-review.md | todo | Step 7 で作成 |
| traceability-map.md | draft | 各工程で更新 |
| traceability-audit.md | todo | Step 9 で作成 |
