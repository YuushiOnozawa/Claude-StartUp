# Test Plan Draft: Core 02

## 自動テスト候補

- リポジトリ外gitプロジェクトで /magi-fast / /magi-hard が完走するか
- bash scripts/、固定codexパス、存在しないagents参照をCIで検出するか
- スキル側モデルとsetup側モデルを突合できるか
- Codex CLI未導入時の扱いを検出できるか

## verify候補

- 実環境に依存する到達性、存在確認、設定整合性を verify に寄せる。
- fail / warn / info の分類は specification.md の未確定事項を解消してから決める。

## CI候補

- 静的に検出できる不整合はCIで検出する。
- grep / 構文チェック / モデル突合 / hooks参照確認など、環境依存の少ない検査を優先する。

## 手動確認候補

- #203 の方針を完遂して references に一本化するか agents を復元するか
- METATRON の devstral を継続するか
- Codex CLI / plugin の確認済みバージョンをどこまで固定するか

## 異常系テスト候補

- 関連Fable項目 01, 02, 03, 06, 08 の不整合を意図的に再現し、検出できるか確認する。
- 依存ツール未導入、設定欠落、環境差、手動ステップ未完了時の挙動を確認する。
- 他核問題と重複する項目は、主担当フォルダのテストと重複であることを明記する。