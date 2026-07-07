# Traceability Map: Core 02 — 実働環境で生まれた開発内容の還流経路が未定義

> 旧核問題名: 「本番 ~/.claude とリポジトリの正が分裂している」
> 旧 PROB/REQ 対応（Fable07/15 × 旧要求）は 2026-07-07 前提変更により全面破棄
> requirements approved: 2026-07-07

## Step 3 — 問題 → 要求（approved 2026-07-07）

| PROB ID | 問題 | 対応 REQ | ステータス |
|---|---|---|---|
| PROB-02-01 | 実働環境で生まれた開発内容が還流されないまま存在し得る（traceability-*, lean-ctx 等が実例） | REQ-02-03, REQ-02-04 | approved |
| PROB-02-02 | 還流漏れを機械的に検知する仕組みがなく、防止が善意に依存している | REQ-02-02, REQ-02-03, REQ-02-08 | approved |
| PROB-02-03 | 両側変更ファイル（MM: CLAUDE.md, skills/pr-review/SKILL.md）の突合が未了 | REQ-02-03, REQ-02-04 | approved |
| PROB-02-04 | 実働環境が76PR遅れの git clone のまま残っており、誤 git pull で大量コンフリクト確定 | REQ-02-01 | approved |

## 要求一覧

| REQ ID | 要求概要 | Fable | ステータス |
|---|---|---|---|
| REQ-02-01 | ~/.claude を通常ディレクトリ化（de-git）。pull 事故防止 | 15 | approved |
| REQ-02-02 | 内容物ホワイトリストの明示定義（内容物 vs ローカルデータの区分） | 15 | approved |
| REQ-02-03 | 還流検知スキル（実働環境と配布原本を突合してファイル一覧を出力） | 15 | approved |
| REQ-02-04 | 検知→PR の運用手順を README に明記 | 07, 15 | approved |
| REQ-02-05 | settings.json は還流・配備の対象外（setup スクリプトが冪等管理） | 15 | approved |
| REQ-02-06 | ローカル専用ファイルは対象外。de-git 後もそのまま残す | 15 | approved |
| REQ-02-07 | 配備ツール（rsync ホワイトリスト方式等）は任意の利便機能 | 15 | approved |
| REQ-02-08 | 還流検知は手動スキルとして提供。利用側（hooks/フロー）への影響なし | 15 | approved |

## 移管記録

- Fable 07 由来の worktree 残骸・.gitignore 整合 → **core-03.4** へ移管（2026-07-07）

## 依存・横断関係

- core-01 REQ-01-01〜07（環境スコープ）→ approved ✅
- core-03.1: agents/leliel.md 削除 → 還流検知の「既知の削除予定物」として記録すれば還流誤爆を防げる
- core-03.3: setup 完遂保証 → 独立した失敗モード（統合しない）
- core-03.4: worktree 残骸・.gitignore 整合の移管先

## 注意

要求・仕様・実装計画・テスト設計の各段階で更新する。
