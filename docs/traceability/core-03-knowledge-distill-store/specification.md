# Specification Draft: Core 03

## 仕様候補

- settings.json直書き方式かsetup動的注入か
- SessionEnd queue push / SessionStart drain の役割
- hooks/logs へのログ統一
- store / vault / index-en の責務とwriter
- pCloud reasonキューの廃止または移行期間
- knowledge-rag API登録と documents_dir + watch の扱い

## 境界条件

- この仕様候補は、分類成果物の「仕様化の観点」から起こした論点であり、まだ確定仕様ではない。
- 関連Fable項目 04, 05, 13 のうち、他の核問題にも現れる項目は重複として扱う。
- 実装確認メモに基づく現状は次の通り。

- settings.json は SessionStart=knowledge-distill / SessionEnd=session-end-queue のキュー方式
- setup/410 は SessionEnd に knowledge-distill を追加登録する
- 410のログパスは hooks/logs と不一致
- 410/411/412/700 は settings.json を動的に書き換える
- 複数 hooks/skills/scripts が ~/pcloud/obsidian と mountpoint に依存
- knowledge-distill は register.sh に登録を委譲し store+watch は未実装

## fail / warn / info の判定が必要なもの

- 目的達成に必須で、欠けると主要機能が動かないものは fail 候補。
- 手動認証、環境差、任意機能、段階導入対象は warn / info 候補。
- 具体的な判定境界は requirements.md の人間確認事項を解消してから決める。

## 未確定事項

- settings.json の正をリポジトリ直書きにするか
- knowledge-rag watch 信頼性を確認してAPI登録を廃止するか
- 既存pCloud/Obsidianデータの初期シード手順