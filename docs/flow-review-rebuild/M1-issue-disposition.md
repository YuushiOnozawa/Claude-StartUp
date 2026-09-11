# Flow/Review 再構築 — M1 Issue disposition

- captured: 2026-09-11
- 母集団: `gh issue list --state open` 全38件から棚卸し

## Issue #411 — クローズ（完了）

プラン策定時（2026-09-08）は「本体凍結、new core の受け入れ条件へ畳む」の想定だったが、その後の
セッションで実装・マージが完了した（PR#420、commit 070aec4）。旧Flow/Reviewシステム上での対応として
完結しているため、当初のD4の想定と異なり**クローズ**とした。TOCTOU重複投稿・Codex broker wedge の
知見はM2の既知事故fixture表（プラン本文に既収録）へそのまま引き継ぐ。

## plangen 関連 — 凍結（クローズせず保留）

| Issue | 内容 | 処置 |
|---|---|---|
| #414 | mktemp/base64失敗時のearly REPORT:FAILUREがHaiku fallback契約と不一致 | 凍結コメント |
| #415 | broker orphan追跡強化（marker scope/SIGKILL窓/sweep retention） | 凍結コメント |
| #416 | CODEX_COMPANION=$(ls...)等の終了コード未捕捉 | 凍結コメント |

plangenスキル自体はarchive対象の20スキルに含まれず、Flow/Review再構築のスコープ外。ただしClaude/Codexの
作業配分上、再構築が一段落するまで着手を見合わせる（M1でのプラン記載通り）。**親Issue #401（PlanGen/
Codexモデルルーティング）自体は凍結していない**——plangenスキルは既に実装・稼働中であり、#401の主要
deliverableは達成済みのため。

## MAGI 関連 — 非アクション化（クローズせず保留）

D6（MAGI(ollama) executorはv1でunavailable stub）により、ハード制約解除まで以下はそもそも動かせない：

| Issue | 内容 |
|---|---|
| #185 | function callingでLLMがdiff自己取得するpull型アーキテクチャ検証 |
| #228 | Ollama tool callループ実装（llm-tools-mcp経由） |
| #243 | METATRONモデルをdevstralからFoundation-Sec-8Bに変更 |
| #306 | granite3.3/phi4のcompletion marker遵守率改善 |
| #344 | METATRON(granite3.3:8b)の30分ハング隔離・調査 |
| #346 | persona反復失敗検出→Codex fallback自動案内 |
| #367 | persona内異常反復（退化ループ）検出・上限ガード |

いずれも「MAGIハード制約解除まで非アクション」である旨コメント済み。ハード制約自体（VRAM/推論速度）が
解決しない限り、これらのIssueの対応可否は再検討できない。

## CASPER — クローズ（新設計に吸収）

| Issue | 内容 | 処置 |
|---|---|---|
| #345 | CASPER(Haiku)のsink実行を実スクリプト化する | クローズ（`executor=claude, model=haiku`の通常personaとして再設計、M6で実装） |

## dev-flow関連 — 保留（クローズせず）

| Issue | 内容 | 処置 |
|---|---|---|
| #331 | codegen/dev-flowにテストゲート導入（commit前の決定論的ゲート） | 保留コメント。v1 DoDには含まれないが再構築後の検討事項として記録 |

## スコープ外（今回ノータッチ）

| Issue | 理由 |
|---|---|
| #270, #383 | `scripts/ollama-run.sh` はプラン本文で明示的に「触らない」対象（Flow/Review以外の消費者が複数あるため） |
| #405 | `codex-companion.mjs` 自体（外部ツール）の制約。M6（Codex executor実装）で関係する可能性はあるが、Flow/Reviewスキル自体のIssueではないため今回は無処置 |
| #65, #79, #80, #86-88, #94, #95, #100, #101, #148, #166, #215, #217, #250, #270, #315, #326, #350, #353, #379, #383 | Flow/Review スコープ外（setup/hooks/knowledge-rag/rtk等） |

## 非目標の確定

プラン本文（`~/.claude/plans/flow-review-agmsg-codex-dreamy-pillow.md` の「目的と非目標」節）で
既に明文化済み（backend×depth組み合わせ手順の個別化禁止／MAGI実装の先送り／旧互換経路なし／
レビュー後段の監査層なし／cross-run cacheなし等、計10項目）。M1で新たに追加すべき非目標は無し。

## M1 ゲート判定

16件に disposition: ✅ 達成（#411クローズ1・plangen凍結3・MAGI非アクション7・CASPERクローズ1・
dev-flow保留1 = 13件処理。残る #401/#405/#270/#383等はスコープ外と明確化）。
**M1 完了**。次は M2（既知事故の fixture 化、コードを書く前の最終ゲート）。
