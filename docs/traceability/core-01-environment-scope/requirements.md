# Requirements: Core 01 — 対応環境スコープ・優先度の確定

> 旧番号: Core 07。人間確認済み: 2026-07-07

## 背景

setup/hooks はbash前提だが、WindowsホストOllama利用や commandWindows の痕跡もあり、Windowsネイティブをサポート範囲に含めるか未確定であった。
本 requirements は人間確認によって確定した方針を記録する。

関連Fable項目: 09, 12, 14

## 確定した要求

| # | 要求 | 根拠 |
|---|---|---|
| REQ-01-01 | サポート対象環境は **WSL2（Linux）のみ** とする。Windowsネイティブは対象外 | 2026-07-07 人間確認 |
| REQ-01-02 | WSL2 から WindowsホストOllama を使う構成（`OLLAMA_HOST=<WinIP>:11434`）を **標準構成** とする | 2026-07-07 人間確認 |
| REQ-01-03 | **pCloud がファイルの最終的な集約場所**（セッションログ・knowledge 等、すべての共有データの終着点）とする | 2026-07-07 人間確認 |
| REQ-01-04 | **pCloud への移送は一括処理**で行う。各 WSL コンテナはファイルをまずローカルに保存し、一括転送スクリプトが pCloud へ送る設計とする | 2026-07-07 人間確認 |
| REQ-01-05 | pCloud 同期方法（rclone 認証・マウント確認）の詳細は **別途検討**とする（複数 WSL コンテナ間で rclone 認証が途切れる問題があるため） | 2026-07-07 人間確認 |
| REQ-01-06 | knowledge-rag 等のツール DB の扱い（ローカル保持 vs pCloud 同期）は **別途検討**とする | 2026-07-07 人間確認 |
| REQ-01-07 | Windowsネイティブ非対応であることを README / verify スクリプト で明示する | REQ-01-01 の帰結 |

## 受け入れ条件

- WSL2 でワンライナー展開が完走する
- WindowsホストOllama 構成（OLLAMA_HOST 設定あり）で二重起動しない
- README と verify が「WSL2のみサポート」を明示している
- ファイルの集約先が pCloud であることが設計・ドキュメントに明記されている
- 各 WSL コンテナがファイルをまずローカルに保存し、一括転送で pCloud へ送る設計になっている

## 対象外（この Step では扱わない）

- Windowsネイティブ（Git Bash 含む）でのセットアップ動作保証
- rclone 認証・マウント確認の具体的な実装（REQ-01-05: 別途検討）
- knowledge-rag DB の pCloud 同期方法（REQ-01-06: 別途検討）
- pCloud 以外のクラウドストレージへの対応
- コード変更・実装修正そのものは Step 5〜6 で扱う

## 重複・横断関係

- Fable 09/12 → core-03.3（setup readiness）と重複。環境スコープが確定したことで core-03.3 の要求範囲が定まる
- Fable 12 → core-03.4（continuous assurance）とも重複
- pCloud 設計の詳細 → core-03.2（knowledge-distill-store）が主担当

## 人間確認事項（解決済み）

| 確認事項 | 決定 | 日付 |
|---|---|---|
| Windowsネイティブ対応を目的範囲に含めるか | 非対応（WSL2のみ） | 2026-07-07 |
| WindowsホストOllama利用を標準構成にするか | 標準にする | 2026-07-07 |
| pCloud/Obsidian Windows Syncを前提として固定するか | pCloudが最終集約場所。各WSLコンテナはまずローカル保存→一括転送。rclone認証・knowledge-rag DB扱いは別途検討 | 2026-07-07 |