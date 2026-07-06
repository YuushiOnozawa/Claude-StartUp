# Core 05: 本番 ~/.claude とリポジトリの正が分裂している

## 核問題名

本番 ~/.claude とリポジトリの正が分裂している

## 関連Fable項目

- 07: リポジトリ衛生
- 15: 本番 ~/.claude クローンの git 状態正常化とデプロイフロー定義

## 関連するリポジトリ目的

- 個人用 ~/.claude/ 共通設定の再現可能な展開
- 新規環境へのワンライナー展開
- 開発フローSKILL

## 問題概要

本番 ~/.claude が未コミット直編集を多く含み、開発リポジトリと正が分裂している。リポジトリが再現可能なセットアップの正であるという前提を弱めている。

## 分類

必須

## confidence

high

## 人間確認が必要な点

- 本番差分をmain反映済み、未マージ実験、ローカル状態に分類すること
- 追跡ファイルの本番直編集を禁止するか
- セッションまとめや調査スクリプトを削除/追跡するか
- **~/.claude を git 配下から外すか（2026-07-06 ユーザー仮説）**: 本番はランタイム変異が常態で
  git 管理と相性が悪く、実運用も既に「開発リポジトリ + 手動コピー」になっている。
  代替案 = ~/.claude を通常ディレクトリ化し、開発リポジトリからの配備スクリプト
  （rsync ホワイトリスト方式）で反映する。採用すると Fable 15 のプラン（pull ベース同期）は
  「de-git + deploy.sh 方式」に差し替えになる。Step 3 で要求として確定させること

## 重複・横断関係

Fable 07 は core-06 と重複する。

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
