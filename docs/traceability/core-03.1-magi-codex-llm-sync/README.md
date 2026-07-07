# Core 03.1: MAGI / Codex / ローカルLLM連携の実体・参照・モデル割当がズレている

> 旧番号: core-02（2026-07-06 実行順に並べ替え）

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
- **agents/leliel.md の削除**（core-02 Step 3 で発覚・2026-07-07 確定）: CASPER 以外の 5 体は同一構造（deepseek-r1:8b）を維持する方針。leliel.md は haiku 固定で設計不整合のため削除する

## 外部先行変更（2026-07-07）

core-02（live-deploy-drift）の Step 3 作業中に以下の設計不整合を発見:

- **発見内容**: `agents/leliel.md` が `model: haiku` で定義されており、他の MAGI 体（Ollama-first）と設計が異なる。magi-hard は `/leliel` スキル経由で呼ぶため agent 定義は実際には使われていないが、直接 `Agent(subagent_type="leliel")` 呼び出しが可能な状態になっており PR #203 の削除理由（スキルフローのバイパス防止）と矛盾する
- **方針**: `agents/leliel.md` を削除し、CASPER 以外の 5 体は deepseek-r1:8b で統一する（2026-07-07 確定）
- **依存**: core-02 の deploy.sh 実装前に完了が必要（deploy.sh が agents/ を配備対象とするため）
- **派生元**: core-02 requirements.md（2026-07-07）

## 重複・横断関係

Fable 02 は core-03.3、03 は core-03.4、08 は core-03.3 と重複する。

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
