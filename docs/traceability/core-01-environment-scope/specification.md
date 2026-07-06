# Specification Draft: Core 07

## 仕様候補

- READMEのサポート環境マトリクス
- WSL2推奨、macOS/Linux動作想定、Windowsネイティブ非対応または限定対応
- 限定対応時のGit Bash、setup.ps1、Linux依存コマンドガード
- Ollama起動判定でWindowsホスト到達性を考慮する

## 境界条件

- この仕様候補は、分類成果物の「仕様化の観点」から起こした論点であり、まだ確定仕様ではない。
- 関連Fable項目 09, 12, 14 のうち、他の核問題にも現れる項目は重複として扱う。
- 実装確認メモに基づく現状は次の通り。

- setup.sh、setup/、hooks/ はbash前提
- setup.ps1 は存在しない
- hooks/lib/ollama.sh はWSL2からWindowsホストOllamaを検出する
- 未追跡 .codex/hooks.json に commandWindows がある
- setup/500-pcloud.sh はWSL2 systemd と rclone mount 前提

## fail / warn / info の判定が必要なもの

- 目的達成に必須で、欠けると主要機能が動かないものは fail 候補。
- 手動認証、環境差、任意機能、段階導入対象は warn / info 候補。
- 具体的な判定境界は requirements.md の人間確認事項を解消してから決める。

## 未確定事項

- Windowsネイティブ対応を目的範囲に含めるか
- WindowsホストOllama利用を標準構成にするか
- pCloud/Obsidian Windows Syncを13の前提として固定するか