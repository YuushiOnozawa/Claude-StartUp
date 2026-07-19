# Design Review: Core 03.2 — hooks / knowledge-distill / 知識ストアの二重化・欠落・密結合

> ステータス: approved（2026-07-19 人間承認済み）
> 実施日: 2026-07-19（Step 7、実装後レビュー）
> レビュー実施者: Codex（gpt-5.6-luna、read-only）。Claude が全指摘をコードで独立検証済み
> 対象: REQ-03.2-01〜04 / SPEC-03.2-01〜05 / IMPL-03.2-01〜05（PR #313/#317/#322/#324 実装済み）

## サマリー

PR-A〜D の hook 登録・ログ統一・キュー移行・ローカル保存は要求↔仕様↔実装が整合している（テスト計 57 件 PASS）。
一方、**knowledge-rag 登録先が MCP サーバー側の `documents_dir`（= `~/pcloud/obsidian`）に依存したまま**であり、
REQ-03.2-03 の受け入れ条件「rclone mount なしで蒸留・knowledge-rag 登録・自動昇格が完走する」は
登録の段で未達（HIGH・保留）。本件は人間判断により **#326 として別トラック化**し、core-03.2 の
hooks 側スコープは完了とする。

## 指摘事項と分類

### [HIGH] 保留（→ Issue 化して別トラック）: knowledge-rag 登録先が pCloud 設定に依存

- **観点**: 要求↔仕様ズレ / 不足実装 / 運用影響
- **内容**: hooks（`knowledge-distill-register.sh:32` / `lessons-learned-distill.sh:142`）は
  `KNOWLEDGE_RAG_DIR=~/.local/share/knowledge-rag` を渡すが、これは config.yaml の発見場所
  （BASE_DIR、`mcp_server/config.py:74`）を変えるだけ。live の config.yaml は
  `documents_dir: /home/ylocal/pcloud/obsidian` を絶対パスで指定しており（`setup/402` が生成）、
  `add_document` は `config.documents_dir / filepath` に書き込む（`mcp_server/server.py:1309-1311`）。
- **影響**:
  - pCloud マウント時: 登録が pcloud-sync.sh 以外の pCloud FUSE 書き込み経路になる（SPEC-01-03 不変条件と競合）
  - pCloud 未マウント時: `config.py:591` の `documents_dir.mkdir(exist_ok=True)` により
    マウントポイント配下に素のローカルディレクトリを作成して書き込み、後続の rclone mount で
    そのファイルが隠れる（データ遮蔽）
- **判断（2026-07-19 人間確認）**: documents_dir の再設計は RAG 検索コーパス全体・core-01
  （pCloud 最終集約点）・core-04（初期シード）に波及するため、core-03.2 の hooks スコープでは
  解消しない。**保留（blocked）として明記し、Issue #326 で追跡**。受け入れ条件のうち
  「knowledge-rag 登録の mount 非依存」は #326 解消まで未達として audit で管理する。

### [MEDIUM] 保留（→ #326 に含めて判断）: 「自動昇格が完走」の定義が REQ と SPEC で不一致

- **観点**: 要求↔仕様ズレ / 曖昧仕様
- **内容**: REQ-03.2-03 受け入れ条件は「mount なしで自動昇格が完走」。SPEC-03.2-03 は
  `knowledge-auto-promote.sh` の pCloud 未マウント時 exit 0 スキップ（graceful）を配送層として容認。
  「完走 = エラーなく終了（スキップ可）」か「実際の昇格完了」かが未定義。
- **判断**: 自動昇格も登録先（documents_dir）に絡むため #326 で「完走」の定義とともに確定する。

### [MEDIUM] 修正済み: specification の自動化対象表に旧配送方針が残存

- **観点**: 仕様↔実装ズレ
- **内容**: `specification.md` の自動化対象表に「pCloud 配送処理の分離（記録完了後のコピー + warn）」
  「pCloud 配送処理の追加（rclone copy + warn）」の旧方針行が残り、本文・実装
  （hook はローカル保存のみ・配送は pcloud-sync.sh 委任）と矛盾していた。
- **対応**: 本レビューで表を「pcloud-sync.sh へ委任（hook は関与しない）」に修正済み。

### [LOW] 保留（→ Step 8 test-plan で拾う）: 成功経路のテスト不足

- **観点**: 不足実装（検証）
- **内容**: 現行テストは登録成功・蒸留済みファイル生成・自動昇格の end-to-end を検証していない
  （Ollama モックの範囲まで）。pCloud 未マウント時の「登録成功」の検証は #326 の解消と対で必要。
- **対応**: Step 8（/traceability-test）のテスト観点に引き継ぐ。

## ブロッカー判定

- hooks 側（SPEC-03.2-01〜05 の実装そのもの）にブロッカーなし。
- REQ-03.2-03 の「knowledge-rag 登録」受け入れ条件は **blocked（#326）** として明記。
  core-03.2 の完了判定（Step 9 audit）ではこの blocked を残指摘として扱い、隠さない。

## 3点セットへの反映

- specification.md: 未確定事項に #4（登録先 documents_dir 依存）を追加、自動化対象表の旧方針行を修正
- README / 全体ボード: design-review = reviewing（人間確認後 approved）
- traceability-map.md: Step 7 行を追加
