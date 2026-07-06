# Implementation Plan Draft: Core 02

## 変更候補ファイル

以下は実装確認メモから抽出した候補であり、このステップでは変更しない。

- agents/ には MAGI 系では leliel.md のみ存在する
- 各personaの SKILL.md に agents/<persona>.md 参照が残る
- 実スキル側モデルと setup/800 のpull対象が一致しない
- magi-fast / magi-hard に bash scripts/... の相対参照が残る
- codegen はCodex委譲だが setup/850 はCodex CLI確認のみ

## 作業単位

- 現状確認を再実施し、Fable項目 01, 02, 03, 06, 08 の指摘が現在も成立するか確認する。
- 要求候補から確定要求を選別する。
- 仕様候補から実装可能な単位へ分割する。
- テスト計画を先に置き、実装後に検証できる形にする。

## PR分割候補

- 主目的に直結する最小修正PR。
- 再発防止のCI / verify / ドキュメント追随PR。
- 移行や運用手順を伴う場合は、実装PRと運用整理PRを分ける。

## 依存関係

- 他核問題との重複: Fable 02 は core-03.3、03 は core-03.4、08 は core-03.3 と重複する。
- core-02 の本番デプロイドリフトが残る場合、実装修正が本番に届かない可能性がある。
- core-03.4 のCI / verify が未整備の場合、再発防止は手動確認に依存する。

## 実装前に決めるべきこと

- #203 の方針を完遂して references に一本化するか agents を復元するか
- METATRON の devstral を継続するか
- Codex CLI / plugin の確認済みバージョンをどこまで固定するか

## 注意

このファイルは実装計画のたたき台であり、コード変更・設定変更の指示ではない。