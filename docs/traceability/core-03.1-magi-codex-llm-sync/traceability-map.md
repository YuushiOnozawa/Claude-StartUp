# Traceability Map: Core 03.1 — MAGI/Codex/ローカルLLM 実体・参照・割当ズレ

> requirements approved: 2026-07-07

## Step 3 — 問題 → 要求

| PROB ID | 問題 | 対応 REQ | ステータス |
|---|---|---|---|
| PROB-03.1-01 | 全ペルソナ SKILL.md に削除済み agents/xxx.md 参照が残存 | REQ-03.1-01 | approved |
| PROB-03.1-02 | agents/leliel.md が haiku 固定・スキルフローをバイパス可能 | REQ-03.1-02 | approved |
| PROB-03.1-03 | magi-fast/hard が bash scripts/... 相対パス参照 | REQ-03.1-04 | approved |
| PROB-03.1-04 | setup/800-ollama-models.sh が WSL2内にモデルをpull（WindowsホストOllama標準構成と矛盾） | REQ-03.1-05 | approved |
| PROB-03.1-05 | execution-steps.md が $AGENT_PATH/agents/ を前提とした Haiku fallback を記述 | REQ-03.1-03 | approved |

## 要求一覧

| REQ ID | 要求概要 | Fable | ステータス |
|---|---|---|---|
| REQ-03.1-01 | 全ペルソナ SKILL.md から agents/xxx.md 参照を削除 | 01 | approved |
| REQ-03.1-02 | agents/leliel.md を削除。LELIEL の Haiku fallback はスキル内で直接呼ぶ | 01 | approved |
| REQ-03.1-03 | execution-steps.md の $AGENT_PATH/agents/ 参照を削除・更新 | 01 | approved |
| REQ-03.1-04 | magi-fast/hard スクリプト参照を $HOME/.claude/scripts/ 絶対パスに修正 | 06 | approved |
| REQ-03.1-05 | setup/800-ollama-models.sh を削除または無効化 | 02 | approved |
| REQ-03.1-06 | SKILL.md の OLLAMA_MODEL 記載を文書として維持（Windows host で必要なモデルの記録） | 02 | approved |
| REQ-03.1-07 | Codex CLI は導入確認のみ維持。動作確認済みバージョンを README に記載 | 08 | approved |

## 依存・横断関係

- core-01 REQ-01-02（WindowsホストOllama標準）→ approved ✅（REQ-03.1-05 の根拠）
- core-02 REQ-02-02（内容物ホワイトリスト）→ agents/ 配備設計と連動
- core-03.3: OLLAMA_HOST 疎通確認・Codex CLI 自動インストール
- core-03.4: SKILLS.md/DESIGN.md ドキュメント陳腐化

## Step 4 — 要求 → 仕様（approved 2026-07-07）

| REQ ID | 対応 SPEC | ステータス |
|---|---|---|
| REQ-03.1-01 | SPEC-03.1-01（全ペルソナ SKILL.md から `エージェント定義` 行削除） | approved |
| REQ-03.1-02 | SPEC-03.1-02（agents/leliel.md を git rm）, SPEC-03.1-03（Haiku fallback を agents/ 非依存に更新） | approved |
| REQ-03.1-03 | SPEC-03.1-03（execution-steps.md の $AGENT_PATH/agents/ 参照除去） | approved |
| REQ-03.1-04 | SPEC-03.1-04（スクリプト相対パスを $HOME/.claude/scripts/ 絶対パスに修正、3箇所。2026-07-14 改訂） | approved |
| REQ-03.1-05 | SPEC-03.1-05（setup/800-ollama-models.sh を git rm） | approved |
| REQ-03.1-06 | SPEC-03.1-06（追加実装なし。SKILL.md の OLLAMA_MODEL 行は維持） | approved |
| REQ-03.1-07 | SPEC-03.1-07（追加実装なし。850-codex.sh は現状維持。core-03.3 に委任） | approved |

## Step 5 — 仕様 → 実装項目（2026-07-16 更新: 全 IMPL 実装済み・テスト PASS のため verified。監査 A-001 対応）

| SPEC ID | 対応 IMPL | ステータス |
|---|---|---|
| SPEC-03.1-01（全ペルソナ SKILL.md エージェント定義行削除） | IMPL-03.1-01（PR #289 で先行消化） | verified |
| SPEC-03.1-02（agents/leliel.md を git rm） | IMPL-03.1-02（PR #289。IMPL-03.1-01 と同時） | verified |
| SPEC-03.1-03（execution-steps.md の agents/ 参照除去・Haiku fallback 更新） | IMPL-03.1-03（PR #289） | verified |
| SPEC-03.1-04（スクリプト相対パスを絶対パスに修正、3箇所。2026-07-14 改訂） | IMPL-03.1-04（PR #308） | verified |
| SPEC-03.1-05（setup/800-ollama-models.sh 削除） | IMPL-03.1-05（PR #307） | verified |
| SPEC-03.1-06（OLLAMA_MODEL 行維持） | IMPL-03.1-06（非変更検証） | verified |
| SPEC-03.1-07（850-codex.sh 現状維持） | IMPL-03.1-07（非変更検証） | verified |

## Step 6 — 実装項目 → 実装参照（2026-07-14 更新）

| IMPL ID | 実装参照 | 状況 |
|---|---|---|
| IMPL-03.1-01 | PR #289（2495b82）— 外部先行変更（core README「外部先行変更（2026-07-14 記録）」参照） | implemented |
| IMPL-03.1-02 | PR #289（同上） | implemented |
| IMPL-03.1-03 | PR #289（同上） | implemented |
| IMPL-03.1-04 | PR #308（c199422。3箇所を絶対パス化。Codex 敵対的レビュー Approve。2026-07-14 マージ） | implemented |
| IMPL-03.1-05 | PR #307（d2822c5。800-ollama-models.sh 削除 + 401 コメント除去。2026-07-14 マージ） | implemented |
| IMPL-03.1-06 | 2026-07-14 検証済み: CASPER 以外の5体に OLLAMA_MODEL 残存。CASPER は PR #198 で Haiku 標準化済みのため行なしが正 | verified |
| IMPL-03.1-07 | PR #307 で検証済み（`git diff setup/850-codex.sh` 差分なし） | verified |

## Step 7 — 設計レビュー（2026-07-16 実施）

| 対象 | レビュー実施者 | 結果 | 記録 |
|---|---|---|---|
| SPEC-03.1-01〜07 + IMPL-03.1-01〜07（実装後レビュー） | Codex（主）+ BALTHASAR（gemma4:e4b-it-qat） | 指摘 6 件 = 修正済み 2（SPEC-03.1-06 を #282 ドリフトで改訂・2026-07-16 再承認済み / implementation-plan PR-A 検証コマンドの CASPER 例外注記）/ 保留 1（live スクリプト同一性確認 → Step 8）/ 対象外 3（850-codex.sh plugin は要求範囲外・#289 互換は別 Epic で E2E 済み・Haiku fallback 根拠は既記載）。design-review は 2026-07-16 人間承認済み | design-review.md |

## Step 8 — 仕様 → テスト（2026-07-16 実施。全 PASS）

| SPEC ID | 対応 TEST | 区分 | 結果 |
|---|---|---|---|
| SPEC-03.1-01 | TEST-03.1-01 | 自動（grep） | PASS |
| SPEC-03.1-02 | TEST-03.1-02（live 側含む） | 自動（ls） | PASS |
| SPEC-03.1-03 | TEST-03.1-03 | 自動（grep） | PASS |
| SPEC-03.1-04 | TEST-03.1-04（静的）+ TEST-03.1-05（別 cwd 手動。2026-07-14 実施分を流用） | 自動 + 手動 | PASS |
| SPEC-03.1-05 | TEST-03.1-06 | 自動（ls + grep） | PASS |
| SPEC-03.1-06 | TEST-03.1-07（改訂仕様の現状値で検証） | 自動（grep） | PASS |
| SPEC-03.1-07 | TEST-03.1-08 | 自動（git log） | PASS |
| （Step 7 保留） | TEST-03.1-09（live/repo スクリプト同一性 5 本） | 自動（cmp） | PASS |

## 注意

要求・仕様・実装計画・テスト設計の各段階で更新する。
