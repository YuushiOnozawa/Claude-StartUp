# Core 03.3: ワンライナー展開後に実行可能状態へ到達する保証が弱い

> 旧番号: core-01（2026-07-06 実行順に並べ替え）

## 核問題名

ワンライナー展開後に実行可能状態へ到達する保証が弱い

## 関連Fable項目

- 02: setup/800-ollama-models.sh とスキルのモデル割当不整合
- 05: error-detector.sh が配備されず自動エラー検知が無音で無効
- 08: Codex CLI の自動インストール不足
- 09: setup 内での Ollama サーバー起動・常駐化不足
- 10: セットアップ統合検証 doctor / verify の不足
- 12: セットアップ後の手動ステップ・チェックリスト不足

## 関連するリポジトリ目的

- 新規環境へのワンライナー展開
- 1スキル1ローカルLLM
- Codex実装・Claudeオーケストラ
- 個人用 ~/.claude/ 共通設定の再現可能な展開

## 問題概要

ワンライナー実行後に、Codex CLI、Ollamaサーバー、必要モデル、hooks、手動認証、verify が一貫した動作可能状態として保証されていない。setup が成功扱いでも、MAGI がフォールバック頼みになる、Codex 実装が使えない、自動エラー検知が無効になる可能性がある。

## 分類

必須

## confidence

high

## 人間確認が必要な点

- Codex未認証を warn にするか info にするか
- 大容量モデルpullをデフォルト必須にするか
- verify の fail / warn 境界

## 重複・横断関係

Fable 02 は core-03.1、05 は core-03.2、10/12 は core-03.4、09/12 は core-01 と重複する。

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
