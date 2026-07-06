# Specification Draft: Core 04

## 仕様候補

- /inbox の検出、確認、調査、還流、台帳更新
- store/vault/inbox、store/knowledge、_inbox-ledger.md の責務
- 経験カードの日英出力、index-en、検索クエリ言語、frontmatter
- auto-recall の発火条件、閾値、上限、timeout、既出抑止
- kizami と knowledge-rag の役割分担

## 境界条件

- この仕様候補は、分類成果物の「仕様化の観点」から起こした論点であり、まだ確定仕様ではない。
- 関連Fable項目 13, 16, 17 のうち、他の核問題にも現れる項目は重複として扱う。
- 実装確認メモに基づく現状は次の通り。

- skills/inbox/ は存在しない
- hooks/auto-recall.sh は存在しない
- store/vault/index-en の分離構造は未実装
- 蒸留系は transcript を .[0:4000] で切っており経験カード形式ではない

## fail / warn / info の判定が必要なもの

- 目的達成に必須で、欠けると主要機能が動かないものは fail 候補。
- 手動認証、環境差、任意機能、段階導入対象は warn / info 候補。
- 具体的な判定境界は requirements.md の人間確認事項を解消してから決める。

## 未確定事項

- /inbox v1 を手動実行に留めるか
- auto-recall 導入前に蒸留カード品質を評価するか
- 英語シャドウノート方式をA/B評価後に確定するか