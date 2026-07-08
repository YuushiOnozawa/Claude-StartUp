# Core 01: 対応環境のスコープと優先度が未確定である

> 旧番号: core-07（2026-07-06 実行順に並べ替え）

## 核問題名

対応環境のスコープと優先度が未確定である

## 関連Fable項目

- 09: setup 内での Ollama サーバー起動・常駐化
- 12: セットアップ後の手動ステップ・チェックリスト整備
- 14: Windows ネイティブ環境対応

## 関連するリポジトリ目的

- 新規環境へのワンライナー展開
- Windows / WSL / Linux の運用範囲
- 個人用 ~/.claude/ 共通設定の再現可能な展開

## 問題概要

setup/hooks はbash前提だが、WindowsホストOllama利用や commandWindows の痕跡もあり、Windowsネイティブをサポート範囲に含めるか未確定である。

## 分類

要確認

## confidence

medium

## 人間確認が必要な点

- Windowsネイティブ対応を目的範囲に含めるか
- WindowsホストOllama利用を標準構成にするか
- pCloud/Obsidian Windows Syncを13の前提として固定するか

## 重複・横断関係

Fable 09/12 は core-03.3、12 は core-03.4 と重複する。

## 注意

このフォルダは作業構造の再配置であり、要求・仕様・実装方針を確定するものではない。
## ステータス

| Document | Status | Notes |
|---|---|---|
| requirements.md | approved | 人間確認・承認済み（2026-07-07） |
| specification.md | approved | SPEC-01-03 追補（不変条件・経験カード追加）。人間承認済み（2026-07-08） |
| implementation-plan.md | approved | PR-A/PR-B(core-03.3 PR-C統合)/PR-C 分割・Codex レビュー対応済み。人間承認済み（2026-07-08） |
| test-plan.md | draft | specification 確定後に更新 |
| design-review.md | todo | Step 7 で作成 |
| traceability-map.md | draft | 各工程で更新 |
| traceability-audit.md | todo | Step 9 で作成 |
