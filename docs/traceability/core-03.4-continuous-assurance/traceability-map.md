# Traceability Map: Core 03.4 — ドキュメント・CI・verify による継続保証

> requirements approved: 2026-07-07

## Step 3 — 問題 → 要求

| PROB ID | 問題 | 対応 REQ | ステータス |
|---|---|---|---|
| PROB-03.4-01 | README.md / DESIGN.md / SKILLS.md が実装と乖離。実装変更時にドキュメント更新が強制されない | REQ-03.4-01 | approved |
| PROB-03.4-02 | .gitignore に .codex/・CLAUDE.local.md 等が未追加（未追跡ファイル滞留） | REQ-03.4-02 | approved |
| PROB-03.4-03 | PR マージ後に worktree ブランチ・作業ファイルが残存する | REQ-03.4-03 | approved |
| PROB-03.4-04 | GitHub Actions CI がなく shellcheck・smoke test が自動化されていない | REQ-03.4-04 | approved |
| PROB-03.4-05 | CI から setup/900-verify.sh を自動実行する仕組みがない（CI 環境の制約から対象外） | — | 対象外（REQ-03.3-03 と境界確認済み） |

## 要求一覧

| REQ ID | 要求概要 | Fable | ステータス |
|---|---|---|---|
| REQ-03.4-01 | 実装変更 PR に対応ドキュメント更新を要求（PR テンプレートのチェックリスト方式） | 03 | approved |
| REQ-03.4-02 | .gitignore に .codex/・CLAUDE.local.md・docs/audit-2026-07-05/・scripts/index-investigations.sh を追加 | 07 | approved |
| REQ-03.4-03 | /finished-pr スキルに worktree ブランチ削除・作業ファイル削除の cleanup ステップを追加 | 07 | approved |
| REQ-03.4-04 | GitHub Actions CI 新設。shellcheck(-S error) + smoke test を自動実行。CI 内では verify スキップ | 11 | approved |

## 依存・横断関係

- core-03.3 REQ-03.3-03（setup/900-verify.sh 新設）→ approved ✅（CI では verify スキップの根拠）
- core-03.3 REQ-03.3-04（README 手動ステップ記載）→ approved ✅（verify の README 導線は 03.3 担当）
- core-02 REQ-02-04（還流スキル化）→ /finished-pr は還流フローの一部
- Fable 10（verify 追加）→ core-03.3 が primary（REQ-03.3-03）。core-03.4 は CI での verify 実行を明示的に対象外とする
- Fable 12（手動ステップ）→ core-03.3 が primary（REQ-03.3-04）。core-03.4 は PR テンプレートのドキュメント更新チェックリストを担当

## Step 4 — 要求 → 仕様

| REQ ID | 対応 SPEC | 備考 |
|---|---|---|
| REQ-03.4-01 | SPEC-03.4-02 | PR テンプレート（.github/pull_request_template.md）でドキュメント更新チェックリスト |
| REQ-03.4-02 | SPEC-03.4-01 | .gitignore に 4エントリ追加（.codex/・CLAUDE.local.md・docs/audit-*/・scripts/index-investigations.sh） |
| REQ-03.4-03 | SPEC-03.4-03 | /finished-pr に作業ファイル削除フェーズ（Phase 6.5: WORKFILES）追加 |
| REQ-03.4-04 | SPEC-03.4-04 | GitHub Actions CI 新設（shellcheck -S error + smoke test）。verify スキップ |

## Step 5 — 仕様 → 実装項目（approved 2026-07-08）

| SPEC ID | 対応 IMPL | PR | ステータス |
|---|---|---|---|
| SPEC-03.4-01（.gitignore 4エントリ追加） | IMPL-03.4-01 | PR-A | approved |
| SPEC-03.4-02（PR テンプレート新設） | IMPL-03.4-02 | PR-B1 | approved |
| SPEC-03.4-03（finished-pr Phase 6.5 追加） | IMPL-03.4-04 | PR-C | approved |
| SPEC-03.4-04（GitHub Actions CI 新設） | IMPL-03.4-03 | PR-B2 | approved |

## 注意

要求・仕様・実装計画・テスト設計の各段階で更新する。
PROB-03.4-05（CI での verify 実行）は OLLAMA_HOST 依存の制約から対象外とした。
verify は新規環境セットアップ時の手動実行として REQ-03.3-03 が担当する。
