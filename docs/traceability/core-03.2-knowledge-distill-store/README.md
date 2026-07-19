# Core 03.2: hooks / knowledge-distill / 知識ストアの基盤が二重化・欠落・密結合している

> 旧番号: core-03（2026-07-06 実行順に並べ替え）

## 核問題名

hooks / knowledge-distill / 知識ストアの基盤が二重化・欠落・密結合している

## 関連Fable項目

- 04: knowledge-distill フック登録の二重化と設計競合
- 05: error-detector.sh が配備されず自動エラー検知が無音で無効
- 13: 知識ストアの疎結合化

## 関連するリポジトリ目的

- 会話ログ蒸留による長期記憶
- Token削減
- 個人用 ~/.claude/ 共通設定の再現可能な展開
- Obsidian / knowledge-rag 連携

## 問題概要

hooks と knowledge-distill に、二重登録、配備漏れ、pCloud/rclone mount への密結合がある。長期記憶の品質、重複登録、トークン消費、再現可能性に影響する。

## 分類

必須

## confidence

high

## 人間確認が必要な点

- settings.json の正をリポジトリ直書きにするか
- knowledge-rag watch 信頼性を確認してAPI登録を廃止するか
- 既存pCloud/Obsidianデータの初期シード手順
- 先行導入される compact 強化フック群を本 core の要求範囲に含めるか（下記）

## 外部先行変更（2026-07-06 記録）

compact 強化セット（compact-prep skill + 復旧 hook + 閾値通知。`compact-hardening-instructions.md`）が
**本 core の対応より先行して jq 動的注入で導入される予定**（監査作業自体を compact 劣化から守る優先度判断）。

- これは本 core の問題クラス「hook 登録の動的注入によるドリフト」の新インスタンスであり、
  Fable 04 の追記（2026-07-06）で「repo 直書きへの移行対象」と記録済み
- Step 3（要求定義）時にこの変更の存在を前提とし、Step 9（監査）で orphan implementation として
  誤検知しないこと（本記録が派生元）

## 外部先行変更（2026-07-16 記録: PR #249 クローズ）

PR #249「refactor(knowledge-distill): transcript依存をなくすためRaw即書き出し設計に変更」
（2026-07-01 作成）は、SessionEnd 直後に Raw .md をローカル保存し以降を transcript 非依存にする構想
（transcript_not_found dead-letter の根絶）だったが、本 core の PR-B（#317）と対象領域が重複し、
2 週間 stale・SPEC-03.2-03 のスコープ外だったため 2026-07-16 にクローズした。

- 記録層のローカル化そのものは PR-B が SPEC 準拠で実装済み
- 「Raw 即書き出し・queue の source_path 汎用化」構想が今後も必要なら、spec 追補
  （SPEC-03.2 系の改訂）を経て別 PR で再実装する
- Step 9（監査）はこのクローズ済み PR を orphan implementation として誤検知しないこと（本記録が派生元）

## 重複・横断関係

Fable 05 は core-03.3、13 は core-04 と重複する。

## 注意

このフォルダは作業構造の再配置であり、要求・仕様・実装方針を確定するものではない。
## ステータス

| Document | Status | Notes |
|---|---|---|
| requirements.md | approved | 人間確認・承認済み（2026-07-07） |
| specification.md | approved | SPEC-03.2-05（lessons-learned ローカル化）追補。人間承認済み（2026-07-08） |
| implementation-plan.md | approved | PR-A/B/C/D 分割・Codex レビュー対応済み。人間承認済み（2026-07-08） |
| 実装 | implemented | PR-A = #313・PR-B = #317（2026-07-16）・PR-C = #322（2026-07-17）・PR-D = #324（2026-07-19）**全 4 PR 完了**、いずれも merge・live 検証済み。ハードニング残件は #315 |
| test-plan.md | approved | 2026-07-19 実行・人間承認済み。既存 3 スクリプト計 57 PASS / 0 FAIL / 0 SKIP。未テスト 2 件は #326（別トラック）待ちで blocked と明記 |
| design-review.md | approved | 2026-07-19 実施（Codex）・人間承認済み。HIGH 1 件は #326 に別トラック化・REQ-03.2-03 の登録/自動昇格は blocked（audit で管理） |
| traceability-map.md | approved | 各工程で更新済み（Step 8 まで反映） |
| traceability-audit.md | verified | 2026-07-19 実施・人間承認済み。orphan/漏れなし。指摘3件（Codex二次確認済み、A-002は本監査で修正済み）。REQ-03.2-03のknowledge-rag登録mount非依存性は#326でblockedとして継続追跡 |
