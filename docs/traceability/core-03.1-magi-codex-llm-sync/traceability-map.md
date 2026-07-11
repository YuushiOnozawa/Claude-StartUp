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
| REQ-03.1-04 | SPEC-03.1-04（スクリプト相対パスを $HOME/.claude/scripts/ 絶対パスに修正、5箇所） | approved |
| REQ-03.1-05 | SPEC-03.1-05（setup/800-ollama-models.sh を git rm） | approved |
| REQ-03.1-06 | SPEC-03.1-06（追加実装なし。SKILL.md の OLLAMA_MODEL 行は維持） | approved |
| REQ-03.1-07 | SPEC-03.1-07（追加実装なし。850-codex.sh は現状維持。core-03.3 に委任） | approved |

## Step 5 — 仕様 → 実装項目（draft）

| SPEC ID | 対応 IMPL | ステータス |
|---|---|---|
| SPEC-03.1-01（全ペルソナ SKILL.md エージェント定義行削除） | IMPL-03.1-01（PR-A） | draft |
| SPEC-03.1-02（agents/leliel.md を git rm） | IMPL-03.1-02（PR-A。IMPL-03.1-01 と同時） | draft |
| SPEC-03.1-03（execution-steps.md の agents/ 参照除去・Haiku fallback 更新） | IMPL-03.1-03（PR-B1） | draft |
| SPEC-03.1-04（スクリプト相対パスを絶対パスに修正、5箇所） | IMPL-03.1-04（PR-B2。PR-B1 と別 PR） | draft |
| SPEC-03.1-05（setup/800-ollama-models.sh 削除） | IMPL-03.1-05（PR-C） | draft |
| SPEC-03.1-06（OLLAMA_MODEL 行維持） | IMPL-03.1-06（非変更検証。PR-A で確認） | draft |
| SPEC-03.1-07（850-codex.sh 現状維持） | IMPL-03.1-07（非変更検証。PR-C で確認） | draft |

## 注意

要求・仕様・実装計画・テスト設計の各段階で更新する。
