# Traceability Map: Core 03.3 — ワンライナー展開後の実行可能状態保証

> requirements approved: 2026-07-07

## Step 3 — 問題 → 要求

| PROB ID | 問題 | 対応 REQ | ステータス |
|---|---|---|---|
| PROB-03.3-01 | setup/850-codex.sh が Codex CLI の確認のみで自動インストールがない | REQ-03.3-01 | approved |
| PROB-03.3-02 | setup/401-ollama.sh が OLLAMA_HOST への疎通確認をしない（WSL2内インストールまでで停止） | REQ-03.3-02 | approved |
| PROB-03.3-03 | ~/.claude/hooks/error-detector.sh の存在確認が setup 完了フローに組み込まれていない | REQ-03.3-03 | approved |
| PROB-03.3-04 | setup.sh に --verify / 900-verify.sh がなく、setup 後の統合状態確認手段がない | REQ-03.3-03 | approved |
| PROB-03.3-05 | README にワンライナー後の手動ステップ・チェックリストがない | REQ-03.3-04 | approved |
| PROB-03.3-06 | setup/800-ollama-models.sh 削除後（REQ-03.1-05）、必要モデルの確認・pull 手段がなくなる | REQ-03.3-03, 04 | approved |

## 要求一覧

| REQ ID | 要求概要 | Fable | ステータス |
|---|---|---|---|
| REQ-03.3-01 | setup/850-codex.sh で Codex CLI を自動インストール。認証は手動ステップとして README に明示 | 08 | approved |
| REQ-03.3-02 | setup/401-ollama.sh を OLLAMA_HOST 疎通確認のみに変更（WSL2内インストール削除）。失敗時 warn | 09 | approved |
| REQ-03.3-03 | setup/900-verify.sh を新設。fail=OLLAMA_HOST疎通不可。warn=Codex未認証・error-detector欠落・モデル不足 | 05, 10, 02 | approved |
| REQ-03.3-04 | README にワンライナー後の手動ステップ一覧と verify 実行案内を記載 | 12 | approved |

## 依存・横断関係

- core-01 REQ-01-02（WindowsホストOllama が前提）→ approved ✅
- core-03.1 REQ-03.1-05（setup/800-ollama-models.sh 削除）→ approved ✅（削除後代替として verify での warn）
- core-03.2 REQ-03.2-04（error-detector.sh 配備）→ approved ✅（verify の確認対象）
- Fable 02 → core-03.1 が primary（REQ-03.1-05/06）。core-03.3 は verify 観点のみ
- Fable 05 → core-03.2 が配備担当（REQ-03.2-04）。core-03.3 は verify 組み込み担当
- core-03.4（CI・verify 継続保証）→ verify の自動実行は core-03.4 が担当

## 注意

要求・仕様・実装計画・テスト設計の各段階で更新する。
