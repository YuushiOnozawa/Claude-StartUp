# Test Plan Draft: Core 03

## 自動テスト候補

- 1 transcript が一度だけ蒸留・登録されるか
- SessionEndにknowledge-distill直接実行が残らないか
- settings.json参照hooksが存在し実行可能か
- rclone mountなしで蒸留・RAG登録・自動昇格できるか
- store/vault同期が一方向で冪等か

## verify候補

- 実環境に依存する到達性、存在確認、設定整合性を verify に寄せる。
- fail / warn / info の分類は specification.md の未確定事項を解消してから決める。

## CI候補

- 静的に検出できる不整合はCIで検出する。
- grep / 構文チェック / モデル突合 / hooks参照確認など、環境依存の少ない検査を優先する。

## 手動確認候補

- settings.json の正をリポジトリ直書きにするか
- knowledge-rag watch 信頼性を確認してAPI登録を廃止するか
- 既存pCloud/Obsidianデータの初期シード手順

## 異常系テスト候補

- 関連Fable項目 04, 05, 13 の不整合を意図的に再現し、検出できるか確認する。
- 依存ツール未導入、設定欠落、環境差、手動ステップ未完了時の挙動を確認する。
- 他核問題と重複する項目は、主担当フォルダのテストと重複であることを明記する。