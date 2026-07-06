# Implementation Plan Draft: Core 01

## 変更候補ファイル

以下は実装確認メモから抽出した候補であり、このステップでは変更しない。

- setup/850-codex.sh は Codex CLI の確認のみで自動インストールしない
- setup/401-ollama.sh はOllamaインストールまででサーバー起動しない
- setup/800-ollama-models.sh は ollama list 失敗時に return 0 でモデル取得をスキップする
- settings.json は hooks/error-detector.sh を参照するが hooks/ に実体がない
- setup.sh に --verify / 900-verify はない

## 作業単位

- 現状確認を再実施し、Fable項目 02, 05, 08, 09, 10, 12 の指摘が現在も成立するか確認する。
- 要求候補から確定要求を選別する。
- 仕様候補から実装可能な単位へ分割する。
- テスト計画を先に置き、実装後に検証できる形にする。

## PR分割候補

- 主目的に直結する最小修正PR。
- 再発防止のCI / verify / ドキュメント追随PR。
- 移行や運用手順を伴う場合は、実装PRと運用整理PRを分ける。

## 依存関係

- 他核問題との重複: Fable 02 は core-02、05 は core-03、10/12 は core-06、09/12 は core-07 と重複する。
- core-05 の本番デプロイドリフトが残る場合、実装修正が本番に届かない可能性がある。
- core-06 のCI / verify が未整備の場合、再発防止は手動確認に依存する。

## 実装前に決めるべきこと

- Codex未認証を warn にするか info にするか
- 大容量モデルpullをデフォルト必須にするか
- verify の fail / warn 境界

## 注意

このファイルは実装計画のたたき台であり、コード変更・設定変更の指示ではない。