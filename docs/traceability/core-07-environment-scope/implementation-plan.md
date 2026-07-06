# Implementation Plan Draft: Core 07

## 変更候補ファイル

以下は実装確認メモから抽出した候補であり、このステップでは変更しない。

- setup.sh、setup/、hooks/ はbash前提
- setup.ps1 は存在しない
- hooks/lib/ollama.sh はWSL2からWindowsホストOllamaを検出する
- 未追跡 .codex/hooks.json に commandWindows がある
- setup/500-pcloud.sh はWSL2 systemd と rclone mount 前提

## 作業単位

- 現状確認を再実施し、Fable項目 09, 12, 14 の指摘が現在も成立するか確認する。
- 要求候補から確定要求を選別する。
- 仕様候補から実装可能な単位へ分割する。
- テスト計画を先に置き、実装後に検証できる形にする。

## PR分割候補

- 主目的に直結する最小修正PR。
- 再発防止のCI / verify / ドキュメント追随PR。
- 移行や運用手順を伴う場合は、実装PRと運用整理PRを分ける。

## 依存関係

- 他核問題との重複: Fable 09/12 は core-01、12 は core-06 と重複する。
- core-05 の本番デプロイドリフトが残る場合、実装修正が本番に届かない可能性がある。
- core-06 のCI / verify が未整備の場合、再発防止は手動確認に依存する。

## 実装前に決めるべきこと

- Windowsネイティブ対応を目的範囲に含めるか
- WindowsホストOllama利用を標準構成にするか
- pCloud/Obsidian Windows Syncを13の前提として固定するか

## 注意

このファイルは実装計画のたたき台であり、コード変更・設定変更の指示ではない。