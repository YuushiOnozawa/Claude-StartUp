# Implementation Plan Draft: Core 06

## 変更候補ファイル

以下は実装確認メモから抽出した候補であり、このステップでは変更しない。

- .github/ は存在しない
- templates/security/github-workflows/security-scan.yml は配布用テンプレート
- scripts/test-*.sh はあるが自動実行CIがない
- setup.sh に --verify はなく setup/900-verify.sh もない
- git状態では audit ディレクトリも未追跡

## 作業単位

- 現状確認を再実施し、Fable項目 03, 07, 10, 11, 12 の指摘が現在も成立するか確認する。
- 要求候補から確定要求を選別する。
- 仕様候補から実装可能な単位へ分割する。
- テスト計画を先に置き、実装後に検証できる形にする。

## PR分割候補

- 主目的に直結する最小修正PR。
- 再発防止のCI / verify / ドキュメント追随PR。
- 移行や運用手順を伴う場合は、実装PRと運用整理PRを分ける。

## 依存関係

- 他核問題との重複: Fable 03 は core-03.1、07 は core-02、10/12 は core-03.3、12 は core-01 と重複する。
- core-02 の本番デプロイドリフトが残る場合、実装修正が本番に届かない可能性がある。
- core-03.4 のCI / verify が未整備の場合、再発防止は手動確認に依存する。

## 実装前に決めるべきこと

- shellcheck厳格度
- smoke testでネットワーク・Ollama・pCloud依存をどこまで扱うか
- CI fail と verify warn の境界
- auditディレクトリを追跡対象にするか

## 注意

このファイルは実装計画のたたき台であり、コード変更・設定変更の指示ではない。