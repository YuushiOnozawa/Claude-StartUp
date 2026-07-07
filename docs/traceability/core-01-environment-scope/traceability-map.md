# Traceability Map: Core 01 — 対応環境スコープ・優先度

> 旧番号: Core 07。requirements approved: 2026-07-07

## Step 3 — 要求（approved 2026-07-07）

| REQ ID | 要求 | 対応 Fable | ステータス |
|---|---|---|---|
| REQ-01-01 | サポート対象環境は WSL2（Linux）のみ。Windowsネイティブは対象外 | 14 | approved |
| REQ-01-02 | WSL2 から WindowsホストOllama（OLLAMA_HOST）を標準構成とする | 09 | approved |
| REQ-01-03 | pCloud がファイルの最終的な集約場所（セッションログ・knowledge 等） | 12 | approved |
| REQ-01-04 | pCloud への移送は一括処理。各 WSL コンテナはまずローカル保存 | 12 | approved |
| REQ-01-05 | pCloud 同期方法（rclone 認証・マウント確認）は別途検討 | 12 | 別途検討 |
| REQ-01-06 | knowledge-rag DB 扱い（ローカル vs pCloud 同期）は別途検討 | 12 | 別途検討 |
| REQ-01-07 | Windowsネイティブ非対応を README / verify で明示 | 14 | approved |

## 重複・横断関係

Fable 09/12 は core-03.3、12 は core-03.4 と重複する。

## 対応表

| Fable項目 | 問題 | 要求候補 | 仕様候補 | 実装項目候補 | テスト観点 | 状態 |
|---|---|---|---|---|---|---|
| 09 | setup 内での Ollama サーバー起動・常駐化。setup/hooks はbash前提だが、WindowsホストOllama利用や commandWindows の痕跡もあり、Windowsネイティブをサポート範囲に含めるか未確定である。 | サポート対象環境を明示する<br>Windowsネイティブを非対応・限定対応・正式対応のどれにするか決める<br>WSLからWindowsホストOllamaを標準想定にするか決める<br>非対応機能を warn とするか対象外とするか決める | READMEのサポート環境マトリクス<br>WSL2推奨、macOS/Linux動作想定、Windowsネイティブ非対応または限定対応<br>限定対応時のGit Bash、setup.ps1、Linux依存コマンドガード<br>Ollama起動判定でWindowsホスト到達性を考慮する | setup.sh、setup/、hooks/ はbash前提<br>setup.ps1 は存在しない<br>hooks/lib/ollama.sh はWSL2からWindowsホストOllamaを検出する<br>未追跡 .codex/hooks.json に commandWindows がある<br>setup/500-pcloud.sh はWSL2 systemd と rclone mount 前提 | WSL2でワンライナーが完走するか<br>WindowsホストOllama構成で二重起動しないか<br>Windows非対応時にREADME/verifyが明示するか<br>限定対応時にGit Bash経由setupが完走し非対応機能がwarnになるか | 未確定 / 要整理 |
| 12 | セットアップ後の手動ステップ・チェックリスト整備。setup/hooks はbash前提だが、WindowsホストOllama利用や commandWindows の痕跡もあり、Windowsネイティブをサポート範囲に含めるか未確定である。 | サポート対象環境を明示する<br>Windowsネイティブを非対応・限定対応・正式対応のどれにするか決める<br>WSLからWindowsホストOllamaを標準想定にするか決める<br>非対応機能を warn とするか対象外とするか決める | READMEのサポート環境マトリクス<br>WSL2推奨、macOS/Linux動作想定、Windowsネイティブ非対応または限定対応<br>限定対応時のGit Bash、setup.ps1、Linux依存コマンドガード<br>Ollama起動判定でWindowsホスト到達性を考慮する | setup.sh、setup/、hooks/ はbash前提<br>setup.ps1 は存在しない<br>hooks/lib/ollama.sh はWSL2からWindowsホストOllamaを検出する<br>未追跡 .codex/hooks.json に commandWindows がある<br>setup/500-pcloud.sh はWSL2 systemd と rclone mount 前提 | WSL2でワンライナーが完走するか<br>WindowsホストOllama構成で二重起動しないか<br>Windows非対応時にREADME/verifyが明示するか<br>限定対応時にGit Bash経由setupが完走し非対応機能がwarnになるか | 未確定 / 要整理 |
| 14 | Windows ネイティブ環境対応。setup/hooks はbash前提だが、WindowsホストOllama利用や commandWindows の痕跡もあり、Windowsネイティブをサポート範囲に含めるか未確定である。 | サポート対象環境を明示する<br>Windowsネイティブを非対応・限定対応・正式対応のどれにするか決める<br>WSLからWindowsホストOllamaを標準想定にするか決める<br>非対応機能を warn とするか対象外とするか決める | READMEのサポート環境マトリクス<br>WSL2推奨、macOS/Linux動作想定、Windowsネイティブ非対応または限定対応<br>限定対応時のGit Bash、setup.ps1、Linux依存コマンドガード<br>Ollama起動判定でWindowsホスト到達性を考慮する | setup.sh、setup/、hooks/ はbash前提<br>setup.ps1 は存在しない<br>hooks/lib/ollama.sh はWSL2からWindowsホストOllamaを検出する<br>未追跡 .codex/hooks.json に commandWindows がある<br>setup/500-pcloud.sh はWSL2 systemd と rclone mount 前提 | WSL2でワンライナーが完走するか<br>WindowsホストOllama構成で二重起動しないか<br>Windows非対応時にREADME/verifyが明示するか<br>限定対応時にGit Bash経由setupが完走し非対応機能がwarnになるか | 未確定 / 要整理 |

## 注意

状態はすべて暫定。要求・仕様・実装計画・テスト設計の各段階で更新する。