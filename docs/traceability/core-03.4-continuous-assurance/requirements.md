# Requirements: Core 03.4 — ドキュメント・CI・verify による継続保証

> 人間確認済み: 2026-07-07

## 背景

実装とドキュメントのズレ、CI 不在、未追跡ファイル滞留、worktree 残骸があり、整合性を継続的に
保証する仕組みが不足している。

関連リポジトリ目的: 目的達成状況の確認、漏れ把握、開発フローSKILL、継続運用と再発防止

関連Fable項目: 03, 07, 10, 11, 12（10/12 は core-03.3 とも重複、07 は core-02 とも重複）

## 適用前提（他 core で確定済み）

- REQ-03.3-03: `setup/900-verify.sh` 新設は core-03.3 担当。core-03.4 は「CI での verify を扱わない」という境界を担当
- REQ-03.3-04: README の手動ステップ記載は core-03.3 担当
- core-02 からの移管: worktree 残骸問題・.gitignore 整合（Fable 07 の問題クラス）

## 問題

| ID | 問題 |
|---|---|
| PROB-03.4-01 | `README.md` / `DESIGN.md` / `SKILLS.md` が実装と乖離している。実装変更時に同一 PR でドキュメントが更新されることが強制されていない |
| PROB-03.4-02 | `.gitignore` に `.codex/`・`CLAUDE.local.md`・`docs/audit-2026-07-05/`・`scripts/index-investigations.sh` が追加されておらず、未追跡ファイルが git status に残り続ける |
| PROB-03.4-03 | PR マージ後に worktree ブランチ・作業ファイルが残存する。`/finished-pr` 等の cleanup ステップが存在しない |
| PROB-03.4-04 | GitHub Actions CI パイプラインがなく、shellcheck・smoke test が自動化されていない |
| PROB-03.4-05 | CI から `setup/900-verify.sh` を自動実行する仕組みがない。ただし CI 環境には OLLAMA_HOST がないため verify の全項目 CI 実行は非現実的（REQ-03.3-03 と境界確認） |

## 確定した要求

| # | 要求 | 根拠 |
|---|---|---|
| REQ-03.4-01 | 実装変更を含む PR には対応するドキュメント更新を要求する（PR テンプレートのチェックリスト方式） | PROB-03.4-01 / Fable 03 / 2026-07-07 確定 |
| REQ-03.4-02 | `.gitignore` に `.codex/`・`CLAUDE.local.md`・`docs/audit-2026-07-05/`・`scripts/index-investigations.sh` を追加し、`git status` をクリーンにする | PROB-03.4-02 / Fable 07 / 2026-07-07 確定 |
| REQ-03.4-03 | `/finished-pr` スキルに worktree ブランチ削除・作業ファイル削除の cleanup ステップを追加する | PROB-03.4-03 / Fable 07 / core-02 移管 / 2026-07-07 確定 |
| REQ-03.4-04 | GitHub Actions CI を新設し、shellcheck（`-S error`、エラーのみ fail）と smoke test を自動実行する。CI 内では `setup/900-verify.sh` はスキップする（OLLAMA_HOST 依存のため） | PROB-03.4-04, 05 / Fable 11 / 2026-07-07 確定 |

### CI チェック項目と fail/warn 境界（REQ-03.4-04 詳細）

| チェック項目 | 判定 | 備考 |
|---|---|---|
| shellcheck -S error（全 .sh ファイル） | fail | error レベルのみ。warning は無視 |
| smoke test（スクリプト dry-run 等） | fail | 実行可能性の確認。ネットワーク・Ollama 依存を含まない |
| setup/900-verify.sh | スキップ | CI 環境に OLLAMA_HOST がないため。手動実行のみ |
| ドキュメント整合チェック | warn / 将来拡張 | 自動化は spec 以降で設計 |

## 受け入れ条件

- PR に shellcheck エラーがあると CI が fail する（warning は無視）
- `.gitignore` 追加後、`git status` に対象ファイルが表示されなくなる
- `/finished-pr` 実行後に worktree ブランチと対応する作業ファイルが残存しない
- GitHub Actions が PR / push 時に自動実行される
- CI は OLLAMA_HOST への疎通確認を行わない（Ollama 依存のテストをスキップする）

## 対象外

- CI での `setup/900-verify.sh` 実行（OLLAMA_HOST 依存のため。verify は新規環境セットアップ時の手動実行のみ）
- ドキュメントと実装の自動同期（PR チェックリストで人間が確認する方式。自動化は spec 以降）
- shellcheck warning レベルの CI 強制（既存スクリプトへの影響が大きいため。error のみ）
- audit ディレクトリの追跡方針（docs/audit-2026-07-05/ は .gitignore 対象として除外。別 PR で管理）
- Fable 10 の verify 自体 → REQ-03.3-03（core-03.3）担当

## 依存関係

- core-03.3 REQ-03.3-03（setup/900-verify.sh 新設）→ approved ✅（CI では verify をスキップする境界の根拠）
- core-02 REQ-02-04（還流スキル化）→ `/finished-pr` は還流フローの一部として位置付け

## 人間確認事項（全件解決済み）

| 確認事項 | 決定 | 日付 |
|---|---|---|
| shellcheck 厳格度 | -S error のみ CI fail。warning は無視 | 2026-07-07 |
| CI での verify 実行 | スキップ。CI は shellcheck + smoke test のみ | 2026-07-07 |
| .gitignore 追加対象 | .codex/・CLAUDE.local.md・docs/audit-2026-07-05/・scripts/index-investigations.sh（全件） | 2026-07-07 |
| worktree 残骸対処 | /finished-pr に cleanup ステップ追加 | 2026-07-07 |
