# Traceability Map: Core 04

## 重複・横断関係

Fable 13 は core-03 と重複する。

## 対応表

| Fable項目 | 問題 | 要求候補 | 仕様候補 | 実装項目候補 | テスト観点 | 状態 |
|---|---|---|---|---|---|---|
| 13 | 知識ストアの疎結合化。長期記憶を保存するだけでなく、Obsidian inbox からの調査還流、経験カード化、auto-recall による横断想起へ進めるための運用仕様が未確定である。 | Obsidian inbox から調査し knowledge へ還流するユーザーストーリー<br>人間領域ノートをClaudeが直接書き換えないこと<br>経験カードに状況・やったこと・結果・判断理由・tech・outcomeを含めること<br>auto-recall は短く必要時だけ注入すること | /inbox の検出、確認、調査、還流、台帳更新<br>store/vault/inbox、store/knowledge、_inbox-ledger.md の責務<br>経験カードの日英出力、index-en、検索クエリ言語、frontmatter<br>auto-recall の発火条件、閾値、上限、timeout、既出抑止<br>kizami と knowledge-rag の役割分担 | skills/inbox/ は存在しない<br>hooks/auto-recall.sh は存在しない<br>store/vault/index-en の分離構造は未実装<br>蒸留系は transcript を .[0:4000] で切っており経験カード形式ではない | inbox URLから調査結果がknowledge化され元メモとリンクされるか<br>search_knowledgeで結果がヒットするか<br>同一メモが二重処理されないか<br>類似タスクで過去経験カードが想起されるか<br>雑談でauto-recallが発火しないか<br>auto-recallが2秒以内に終わるか | 未確定 / 要整理 |
| 16 | Obsidian 第2の脳ワークフロー。長期記憶を保存するだけでなく、Obsidian inbox からの調査還流、経験カード化、auto-recall による横断想起へ進めるための運用仕様が未確定である。 | Obsidian inbox から調査し knowledge へ還流するユーザーストーリー<br>人間領域ノートをClaudeが直接書き換えないこと<br>経験カードに状況・やったこと・結果・判断理由・tech・outcomeを含めること<br>auto-recall は短く必要時だけ注入すること | /inbox の検出、確認、調査、還流、台帳更新<br>store/vault/inbox、store/knowledge、_inbox-ledger.md の責務<br>経験カードの日英出力、index-en、検索クエリ言語、frontmatter<br>auto-recall の発火条件、閾値、上限、timeout、既出抑止<br>kizami と knowledge-rag の役割分担 | skills/inbox/ は存在しない<br>hooks/auto-recall.sh は存在しない<br>store/vault/index-en の分離構造は未実装<br>蒸留系は transcript を .[0:4000] で切っており経験カード形式ではない | inbox URLから調査結果がknowledge化され元メモとリンクされるか<br>search_knowledgeで結果がヒットするか<br>同一メモが二重処理されないか<br>類似タスクで過去経験カードが想起されるか<br>雑談でauto-recallが発火しないか<br>auto-recallが2秒以内に終わるか | 未確定 / 要整理 |
| 17 | プロジェクト横断の長期記憶活用。長期記憶を保存するだけでなく、Obsidian inbox からの調査還流、経験カード化、auto-recall による横断想起へ進めるための運用仕様が未確定である。 | Obsidian inbox から調査し knowledge へ還流するユーザーストーリー<br>人間領域ノートをClaudeが直接書き換えないこと<br>経験カードに状況・やったこと・結果・判断理由・tech・outcomeを含めること<br>auto-recall は短く必要時だけ注入すること | /inbox の検出、確認、調査、還流、台帳更新<br>store/vault/inbox、store/knowledge、_inbox-ledger.md の責務<br>経験カードの日英出力、index-en、検索クエリ言語、frontmatter<br>auto-recall の発火条件、閾値、上限、timeout、既出抑止<br>kizami と knowledge-rag の役割分担 | skills/inbox/ は存在しない<br>hooks/auto-recall.sh は存在しない<br>store/vault/index-en の分離構造は未実装<br>蒸留系は transcript を .[0:4000] で切っており経験カード形式ではない | inbox URLから調査結果がknowledge化され元メモとリンクされるか<br>search_knowledgeで結果がヒットするか<br>同一メモが二重処理されないか<br>類似タスクで過去経験カードが想起されるか<br>雑談でauto-recallが発火しないか<br>auto-recallが2秒以内に終わるか | 未確定 / 要整理 |

## 注意

状態はすべて暫定。要求・仕様・実装計画・テスト設計の各段階で更新する。