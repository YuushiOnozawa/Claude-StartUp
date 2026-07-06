# Requirements Draft: Core 03

## 背景

hooks と knowledge-distill に、二重登録、配備漏れ、pCloud/rclone mount への密結合がある。長期記憶の品質、重複登録、トークン消費、再現可能性に影響する。

関連Fable項目: 04, 05, 13

## 問題

この核問題では、分類成果物で整理された問題を要求定義へ進める前段階として扱う。ここに書く内容は要求候補であり、確定要求ではない。

## 要求候補

- 蒸留は1 transcript につき1回だけ処理される
- hooks の登録元、ログ出力先、配備対象を明確にする
- 記録層はローカルstoreで完結する
- 配送層と取込層は一方向同期にする
- error-detector の配備と実行コスト上限を要求する

## 受け入れ条件候補

- 1 transcript が一度だけ蒸留・登録されるか
- SessionEndにknowledge-distill直接実行が残らないか
- settings.json参照hooksが存在し実行可能か
- rclone mountなしで蒸留・RAG登録・自動昇格できるか
- store/vault同期が一方向で冪等か

## 対象外候補

- コード変更・実装修正そのものは、この整理ステップでは対象外。
- 関連ドキュメントの最終文言確定は、要求確定後の別作業とする。
- 他の核問題で主担当となる項目は、このフォルダでは重複関係として扱う。

## 人間確認事項

- settings.json の正をリポジトリ直書きにするか
- knowledge-rag watch 信頼性を確認してAPI登録を廃止するか
- 既存pCloud/Obsidianデータの初期シード手順

## 重複・横断関係

Fable 05 は core-03.3、13 は core-04 と重複する。