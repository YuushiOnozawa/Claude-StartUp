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

## Step 4 — 要求 → 仕様（approved 2026-07-07）

| REQ ID | 対応 SPEC | ステータス |
|---|---|---|
| REQ-02-01 | SPEC-02-01（de-git 実行仕様） | approved |
| REQ-02-02 | SPEC-02-02（ホワイトリスト定義ファイル） | approved |
| REQ-02-03 | SPEC-02-03（還流検知スクリプト `/sync-check`） | approved |
| REQ-02-04 | SPEC-02-04（還流手順の文書化とスキル化） | approved |
| REQ-02-05 | SPEC-02-05（settings.json とローカルデータの除外保証） | approved |
| REQ-02-06 | SPEC-02-05（ローカルデータの除外保証） | approved |
| REQ-02-07 | SPEC-02-06（配備ツール: 本 core では実装しない） | approved |
| REQ-02-08 | SPEC-02-07（手動スキルのみの保証） | approved |

## 移管記録

- Fable 07 由来の worktree 残骸・.gitignore 整合 → **core-03.4** へ移管（2026-07-07）

## 依存・横断関係

- core-01 REQ-01-01〜07（環境スコープ）→ approved ✅
- core-03.1: agents/leliel.md 削除 → 還流検知の「既知の削除予定物」として記録すれば還流誤爆を防げる
- core-03.3: setup 完遂保証 → 独立した失敗モード（統合しない）
- core-03.4: worktree 残骸・.gitignore 整合の移管先

## Step 5 — 仕様 → 実装項目（approved 2026-07-07）

| SPEC ID | 対応 IMPL | ステータス | 実装参照 |
|---|---|---|---|
| SPEC-02-01（de-git 実行仕様） | IMPL-02-05（README に de-git 手順を記載） | ✅ implemented | PR #280 |
| SPEC-02-02（ホワイトリスト定義ファイル） | IMPL-02-01（scripts/sync-whitelist.conf 新設） | ✅ implemented | commit 6955706 |
| SPEC-02-03（還流検知スクリプト /sync-check） | IMPL-02-02（sync-known-deletions.conf 新設）, IMPL-02-03（sync-check.sh 新設）, IMPL-02-04（SKILL.md 新設） | ✅ implemented | commit 6955706, e82ba74 |
| SPEC-02-04（還流手順の文書化） | IMPL-02-05（README.md 還流手順セクション追加） | ✅ implemented | PR #280 |
| SPEC-02-05（settings.json 除外保証） | IMPL-02-01 で担保（追加実装なし） | ✅ implemented | commit 6955706 |
| SPEC-02-06（配備ツール実装指針） | 本 core では実装しない | ✅ n/a | — |
| SPEC-02-07（手動スキルのみ保証） | settings.json を変更しないことで担保（追加実装なし） | ✅ n/a | — |

## Step 9 Audit 引き継ぎ（既知 Low）

PR #280 レビュー（MAGI-HARD 2026-07-11）で確認された既知の制約。audit（Step 9）で対応要否を判断する。

| # | 内容 | 方向 |
|---|---|---|
| 1 | `sync-check.sh` は include パターン3形式（`/dir/***`・`/dir/*.sh`・`/単一パス`）のみ対応。未知パターンは**無警告スキップ**（偽陰性方向） | warn 化を audit で検討 |
| 2 | exclude 行（`-` プレフィックス）は `sync-check.sh` の検知ロジックで非評価（rsync セマンティクスと非対称） | 現状は whitelist 設計で担保済み。audit で再確認 |
| 3 | `known_deletions` 判定は「新規」側のみ（実働・repo 両側に存在して差分がある場合は「要還流（変更）」になる） | 仕様想定内。audit でドキュメント化 |
| 4 | `compare_recursive` で `diff` がエラーを返したファイルは分類から漏れうる（stderr に出力はされる） | 安全方向（偽陽性）ではないため audit で warn 追加を検討 |

## Step 7 — 設計レビュー（2026-07-11）

| 指摘 ID | 重大度 | 内容 | 分類 | 対応先 |
|---|---|---|---|---|
| DR-02-01 | HIGH | `diff -rq` は rsync exclude 形式を解釈しない | **修正済み（実装で対処）** | sync-check.sh は include パスのみ反復処理。exclude 行は rsync 用文書として存在 |
| DR-02-02 | MEDIUM | 配布原本のみに存在するファイルの分類が未定義 | **修正済み（実装で対処）** | 一方向比較（実働→配布原本のみ検知）を実装で担保。SPEC-02-03 補足追記を推奨 |
| DR-02-03 | MEDIUM | 中断時の終了コードが未確定 | **修正済み（実装で対処）** | exit 2/1/0 で実装済み |
| DR-02-04 | LOW | `--verbose` の出力粒度が未定義 | **保留** | 仕様補足推奨（ブロッカーではない） |
| — | — | レビュー実施者 | Codex（read-only） | — |

## Step 8 — 仕様 → テスト（2026-07-11）

| SPEC ID | 対応 TEST ID | 区分 | 結果 |
|---|---|---|---|
| SPEC-02-01（de-git） | TEST-02-01-01, TEST-02-01-02 | 手動確認 | **PASS**（2026-07-11 de-git 実施済み） |
| SPEC-02-02（whitelist） | TEST-02-02-01〜03 | 自動/verify | **PASS** |
| SPEC-02-03（sync-check.sh） | TEST-02-03-01〜11（scripts/test-sync-check.sh 流用） | 自動/CI/verify | **11 PASS / 0 FAIL / 0 SKIP**（TEST-02-03-11 実環境 verify 含む。reflux-inventory-2026-07-11.md 参照） |
| SPEC-02-04（手順文書化） | TEST-02-04-01〜02 | 自動/手動 | **PASS（TEST-01 のみ。TEST-02 は手動確認要）** |
| SPEC-02-05（除外保証） | TEST-02-02-03, TEST-02-03-07 で担保 | — | **PASS** |
| SPEC-02-06（配備ツール） | 未実装のためテスト対象外 | — | n/a |
| SPEC-02-07（手動スキルのみ） | TEST-02-07-01 | verify | **PASS** |

## Step 9 — 監査（2026-07-11）

| 指摘 ID | 重大度 | 内容 | Codex 判定 | 最終分類 |
|---|---|---|---|---|
| A-001 | MEDIUM | 受入条件「初回の還流棚卸し + MM ファイル取捨判断の記録」に SPEC/IMPL/TEST なし | valid | **解消**（2026-07-11 初回棚卸し実施・取捨判断記録済み。reflux-inventory-2026-07-11.md 参照） |
| A-002 | LOW | 未知パターン無警告スキップ（偽陰性） | valid | **保留**（whitelist.conf 変更時の注意事項として記録） |
| A-003 | LOW | diff エラー時の分類漏れ（exit 0 になり得る） | valid | **保留**（運用で対処・将来改善候補） |
| A-004 | LOW | known-deletions の適用範囲（新規のみ）が仕様に未明記 | valid | **保留**（SPEC-02-03 に補足追記済み） |

## 注意

要求・仕様・実装計画・テスト設計の各段階で更新する。
