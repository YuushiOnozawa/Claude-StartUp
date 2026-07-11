# Test Plan Draft: Core 07

## 自動テスト候補

- WSL2でワンライナーが完走するか
- WindowsホストOllama構成で二重起動しないか
- Windows非対応時にREADME/verifyが明示するか
- 限定対応時にGit Bash経由setupが完走し非対応機能がwarnになるか

## verify候補

- 実環境に依存する到達性、存在確認、設定整合性を verify に寄せる。
- fail / warn / info の分類は specification.md の未確定事項を解消してから決める。

## CI候補

- 静的に検出できる不整合はCIで検出する。
- grep / 構文チェック / モデル突合 / hooks参照確認など、環境依存の少ない検査を優先する。

## 手動確認候補

- Windowsネイティブ対応を目的範囲に含めるか
- WindowsホストOllama利用を標準構成にするか
- pCloud/Obsidian Windows Syncを13の前提として固定するか

## 異常系テスト候補

- 関連Fable項目 09, 12, 14 の不整合を意図的に再現し、検出できるか確認する。
- 依存ツール未導入、設定欠落、環境差、手動ステップ未完了時の挙動を確認する。
- 他核問題と重複する項目は、主担当フォルダのテストと重複であることを明記する。