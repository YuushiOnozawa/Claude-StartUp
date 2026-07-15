# Design Review: Core 03.1 — MAGI / Codex / ローカルLLM連携の実体・参照・割当ズレ

> ステータス: approved（2026-07-16 実施・同日人間承認済み）
> レビュー実施者: **Codex**（主）+ **BALTHASAR**（Ollama `gemma4:e4b-it-qat`。先行実施）
> 経緯: quota 節約方針（2026-07-13）により BALTHASAR で先行実施 → ユーザー許可を得て Codex レビューを追加実施し統合
> 実施タイミング: 実装後（全 IMPL 完了 2026-07-14 の事後レビュー）

## レビュー入力

- PLAN_TEXT: specification.md（SPEC-03.1-01〜07、SPEC-04 は 2026-07-14 改訂版）+ implementation-plan.md 要点 + 実装状況
- REVIEW_CONTEXT: core-03.1 README 概要 + 外部先行変更（PR #289）
- REVIEW_CONSTRAINTS: requirements.md「対象外」セクション + 承認済み REQ-03.1-01〜07（変更禁止領域）

## 指摘と判定

各指摘は Claude が現物（スキルファイル・git 履歴）と突合して判定した。

### 指摘 1 [Codex: HIGH → 判定: 正当。ドキュメント反映済み・spec 再承認待ち]

**内容**: REQ/SPEC-03.1-06 のモデル割当と実装が不一致。仕様は LELIEL=`deepseek-r1:8b`・METATRON=`devstral:latest` だが、実装は LELIEL=`llama3.1:8b`（skills/leliel/SKILL.md:16）・METATRON=`granite3.3:8b`（skills/metatron/SKILL.md:15）。

**判定: 修正済み（記録・改訂対応。2026-07-16）**
- git 履歴で確認: PR #282（fix: METATRON/LELIEL のモデルを VRAM 制約に適合、2026-07-12 マージ）が仕様承認（2026-07-07）後に両モデルを変更した未記録ドリフト
- モデル変更自体はユーザー決定済み（VRAM 制約適合）のため、モデルを仕様値へ戻すのではなく仕様を現状へ改訂する（SPEC-03.1-04 の #289 ドリフト対応と同じ手続き）
- 対応: README に「外部先行変更（2026-07-16 記録）」を追加、SPEC-03.1-06 を現状値に改訂 → 2026-07-16 人間再承認済み（spec は approved に復帰）

### 指摘 2 [Codex: MEDIUM → 判定: 対象外（承認時点の現状）]

**内容**: REQ-03.1-07「導入確認のみ」と setup/850-codex.sh が不一致。未導入時に marketplace 登録と plugin install を実行する。

**判定: 対象外**
- 850-codex.sh は PR #255（2026-07-03）で作成され、plugin 自動インストールは要求承認（2026-07-07）時点で既存の「現状」
- REQ-03.1-07 の文言は「**Codex CLI** は導入確認のみ」であり、CLI 部分は確認のみを維持している（`npm install` は実行しない）。plugin インストールは要求の範囲外
- Codex CLI 本体の自動インストール実装は core-03.3 スコープ（requirements「対象外」に明記済み）。plugin 自動インストールの扱いを明確化したい場合は core-03.3 の要求定義で扱う

### 指摘 3 [Codex: MEDIUM → 判定: 保留（Step 8 + core-02 契約）]

**内容**: `$HOME/.claude/scripts/` への絶対パス化に配備元との整合性確認がない。repo 側 `scripts/` と live 側のコピーが乖離すると古いフィルタを実行する可能性がある。

**判定: 保留**
- 配備契約（repo → `~/.claude/` の還流・sync-check）は core-02 の還流フローが担う（verified 済み）
- 残るリスクは「還流漏れ時に古い live スクリプトが動く」こと。Step 8 test-plan に「live 側スクリプトと repo 側の同一性確認」を観点として追加する

### 指摘 4 [Codex: MEDIUM → 判定: 対象外（別 Epic スコープ）]

**内容**: PR #289（execution-steps.md 大規模書き換え）の sink/legacy mode 後方互換性を検証する自動テストが不足。

**判定: 対象外**
- #289 は MAGI-HARD トリアージ再設計 Epic（全 7 Feature、2026-07-13 完了）のスコープであり、同 Epic で live 配備 + E2E 検証済み。poster 系の自動テスト（scripts/tests/）も同 Epic で整備
- core-03.1 のテスト範囲は SPEC-03.1-01〜07 の受け入れ条件（Step 8 で設計）

### 指摘 5 [BALTHASAR: HIGH → 判定: 誤検知（残差のみ修正済み）]

**内容**: 「REQ-03.1-01/02 の参照削除要求に対し、IMPL-06/07 検証で『OLLAMA_MODEL 行なし』という結果が出ており仕様と実装の整合性が取れていない」

**判定: 対象外（誤検知）＋残差は修正済み**
- REQ-03.1-01/02 は充足済み。2026-07-16 再確認: 6ペルソナ SKILL.md + execution-steps.md に `agents/` 参照 0 件、`agents/leliel.md` 不存在（BALTHASAR が IMPL-06 の検証コマンド注記を要求未達と誤読）
- 実体のある残差: implementation-plan.md PR-A 検証コマンドの「各ファイル 1 match」に CASPER 例外（PR #198 で OLLAMA_MODEL 行なしが正）の注記を追加した（2026-07-16 修正済み）

### 指摘 6 [BALTHASAR: MEDIUM → 判定: 対象外（既記載）]

**内容**: 「Haiku fallback が特定ファイル群に限定される理由・設計思想が不明瞭」

**判定: 対象外（既記載）**
- SPEC-03.1-03 事後条件「Ollama パスと Haiku fallback パスで参照するファイル群が一致している」および「確定した仕様上の決定」#2（2026-07-07 人間確認済み）に根拠記載済み

## レビュー観点ごとの結果

| 観点 | 結果 |
|---|---|
| 要求と仕様のズレ | SPEC-03.1-06 のモデル名が PR #282 でドリフト → 改訂・再承認待ち（指摘 1）。他はなし |
| 仕様と実装項目のズレ | PR-A 検証コマンドの CASPER 例外注記漏れのみ → 修正済み（指摘 5 残差） |
| 過剰実装・不足実装・曖昧仕様 | 850-codex.sh の plugin 自動インストールは要求範囲外の既存現状（指摘 2）。core-03.3 で明確化 |
| 後方互換性 | #289 の sink/legacy 互換は別 Epic で E2E 済み（指摘 4）。本 core の変更（削除・パス固定）に互換問題なし |
| 運用影響 | live 反映済み・バックアップあり。live スクリプト同一性確認を Step 8 観点に追加（指摘 3） |
| セキュリティ影響 | なし（削除・パス固定のみ。絶対パス化は cwd 依存の誤実行を防ぐ方向） |

## 分類サマリ

| # | 指摘 | レビュアー/重大度 | 分類 |
|---|---|---|---|
| 1 | SPEC-03.1-06 モデル割当ドリフト（PR #282） | Codex / HIGH | 修正済み（spec 改訂・再承認待ち） |
| 2 | 850-codex.sh plugin 自動インストールと「確認のみ」の不一致 | Codex / MEDIUM | 対象外（要求範囲は CLI。core-03.3 で明確化） |
| 3 | $HOME/.claude/scripts 配備整合性の確認不足 | Codex / MEDIUM | 保留（Step 8 観点に追加） |
| 4 | #289 sink/legacy 互換の自動テスト不足 | Codex / MEDIUM | 対象外（別 Epic で E2E 済み） |
| 5 | REQ-01/02 と検証結果の不整合 | BALTHASAR / HIGH | 対象外（誤検知）。残差の注記のみ修正済み |
| 6 | Haiku fallback 限定理由が不明瞭 | BALTHASAR / MEDIUM | 対象外（SPEC-03.1-03 に既記載） |

## 結論

- 重大な仕様漏れ: **1 件検出・対応済み**（SPEC-03.1-06 のモデル割当ドリフト。仕様改訂で吸収、人間再承認待ち）
- 実装自体の欠陥: なし（REQ-01〜05/07 の受け入れ条件は現物確認で全て充足）
- 保留 1 件（live スクリプト同一性確認）は Step 8 test-plan の観点に引き継ぐ
