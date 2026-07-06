# Implementation Plan Draft: Core 03

## 変更候補ファイル

以下は実装確認メモから抽出した候補であり、このステップでは変更しない。

- settings.json は SessionStart=knowledge-distill / SessionEnd=session-end-queue のキュー方式
- setup/410 は SessionEnd に knowledge-distill を追加登録する
- 410のログパスは hooks/logs と不一致
- 410/411/412/700 は settings.json を動的に書き換える
- 複数 hooks/skills/scripts が ~/pcloud/obsidian と mountpoint に依存
- knowledge-distill は register.sh に登録を委譲し store+watch は未実装

## 作業単位

- 現状確認を再実施し、Fable項目 04, 05, 13 の指摘が現在も成立するか確認する。
- 要求候補から確定要求を選別する。
- 仕様候補から実装可能な単位へ分割する。
- テスト計画を先に置き、実装後に検証できる形にする。

## PR分割候補

- 主目的に直結する最小修正PR。
- 再発防止のCI / verify / ドキュメント追随PR。
- 移行や運用手順を伴う場合は、実装PRと運用整理PRを分ける。

## 依存関係

- 他核問題との重複: Fable 05 は core-03.3、13 は core-04 と重複する。
- core-02 の本番デプロイドリフトが残る場合、実装修正が本番に届かない可能性がある。
- core-03.4 のCI / verify が未整備の場合、再発防止は手動確認に依存する。

## 実装前に決めるべきこと

- settings.json の正をリポジトリ直書きにするか
- knowledge-rag watch 信頼性を確認してAPI登録を廃止するか
- 既存pCloud/Obsidianデータの初期シード手順

## 注意

このファイルは実装計画のたたき台であり、コード変更・設定変更の指示ではない。