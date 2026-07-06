# Traceability Map: Core 07

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