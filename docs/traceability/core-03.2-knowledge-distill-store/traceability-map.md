# Traceability Map: Core 03.2 — hooks / knowledge-distill / 知識ストアの二重化・欠落・密結合

> requirements approved: 2026-07-07

## Step 3 — 問題 → 要求

| PROB ID | 問題 | 対応 REQ | ステータス |
|---|---|---|---|
| PROB-03.2-01 | setup/410 が SessionEnd に knowledge-distill.sh を直接追加し settings.json キュー方式と競合（二重蒸留） | REQ-03.2-01 | approved |
| PROB-03.2-02 | setup/410 ログパスと settings.json ログパスが不一致（hooks/ vs hooks/logs/） | REQ-03.2-02 | approved |
| PROB-03.2-03 | setup/410-412-700 が settings.json を動的書き換え（設計事項として spec 以降で扱う。独立 REQ なし） | — | 設計事項 |
| PROB-03.2-04 | hooks/skills が ~/pcloud/obsidian mount に密結合・rclone 未起動で失敗 | REQ-03.2-03 | approved |
| PROB-03.2-05 | error-detector.sh が新規環境の hooks/ に存在せず PostToolUse が無音で無効 | REQ-03.2-04 | approved |
| PROB-03.2-06 | compact 強化フック群（PR #267）が動的注入で先行導入済み（audit のみで管理。独立 REQ なし） | — | audit対象 |

## 要求一覧

| REQ ID | 要求概要 | Fable | ステータス |
|---|---|---|---|
| REQ-03.2-01 | SessionEnd は queue push のみ。knowledge-distill.sh 直接実行を settings.json/setup から除去 | 04 | approved |
| REQ-03.2-02 | hook ログ出力先を hooks/logs/ 配下に統一（setup/410 のパス修正） | 04 | approved |
| REQ-03.2-03 | 記録層は rclone mount なしで完結。pCloud/Obsidian へは配送層として分離 | 04, 13 | approved |
| REQ-03.2-04 | error-detector.sh を hooks/ に配備。PostToolUse で実行可能な状態を保証 | 05 | approved |

## 依存・横断関係

- core-02 REQ-02-05（settings.json は還流・配備対象外）→ approved ✅
- core-01 REQ-01-03（pCloud は最終集約点）→ approved ✅
- Fable 05 → core-03.3（error-detector の setup verify 組み込み）と重複
- Fable 13 → core-04（知識ストア疎結合化の詳細設計）と重複

## Step 4 — 要求 → 仕様（approved 2026-07-07）

| REQ ID | 対応 SPEC | ステータス |
|---|---|---|
| REQ-03.2-01 | SPEC-03.2-01（setup/410 の SessionEnd 登録削除 + SessionStart 移行） | approved |
| REQ-03.2-02 | SPEC-03.2-02（setup/410 log path を hooks/logs/ に統一） | approved |
| REQ-03.2-03 | SPEC-03.2-03（knowledge-distill.sh の記録層を pCloud 非依存化・配送層分離）・SPEC-03.2-05（lessons-learned パイプラインをローカル保存に統一）| approved |
| REQ-03.2-04 | SPEC-03.2-04（hooks/error-detector.sh リポジトリ追加 + setup/413 新設） | approved |

## Step 5/6 — 仕様 → 実装項目

| SPEC ID | 対応 IMPL | PR | ステータス |
|---|---|---|---|
| SPEC-03.2-01（setup/410 SessionEnd→SessionStart 移行） | IMPL-03.2-01 | PR-A = [#313](https://github.com/YuushiOnozawa/Claude-StartUp/pull/313) | implemented（2026-07-16 merge・live 検証 4 項目 OK） |
| SPEC-03.2-02（setup/410 log path 統一） | IMPL-03.2-01（PR-A で同時） | PR-A = [#313](https://github.com/YuushiOnozawa/Claude-StartUp/pull/313) | implemented（2026-07-16 merge・live 検証 4 項目 OK） |
| SPEC-03.2-03（knowledge-distill.sh 記録層/配送層分離） | IMPL-03.2-02 | PR-B = [#317](https://github.com/YuushiOnozawa/Claude-StartUp/pull/317) | implemented（2026-07-16 merge・live 検証 OK。drain 条件の仕様改訂は spec 注記参照） |
| SPEC-03.2-04（error-detector.sh リポジトリ追加） | IMPL-03.2-03 | PR-C = [#322](https://github.com/YuushiOnozawa/Claude-StartUp/pull/322)（repo 追加は core-02 還流 PR-R4 で先行完了） | implemented（2026-07-17 merge・live 検証 OK） |
| SPEC-03.2-05（lessons-learned ローカル化 + CLAUDE.md 変更） | IMPL-03.2-04, IMPL-03.2-05 | PR-D = [#324](https://github.com/YuushiOnozawa/Claude-StartUp/pull/324) | implemented（2026-07-19 merge・live 検証 OK。手動保存スコープ外の仕様注記は spec 参照） |

## Step 7 — 設計レビュー

| 対象 | 実施 | 結果 |
|---|---|---|
| REQ↔SPEC↔IMPL 整合（実装後） | 2026-07-19 Codex（Claude がコード検証） | design-review.md 参照。HIGH 1 件（knowledge-rag 登録先の documents_dir 依存）= [#326](https://github.com/YuushiOnozawa/Claude-StartUp/issues/326) 別トラック化・REQ-03.2-03 の登録/自動昇格の受け入れ条件は blocked。MEDIUM の旧配送方針行は修正済み。LOW は Step 8 test-plan へ |

## 注意

要求・仕様・実装計画・テスト設計の各段階で更新する。
PROB-03.2-03（settings.json 動的注入）は spec の設計事項として扱い、独立 REQ は設けない。
PROB-03.2-06（compact フック）は Step 9（audit）で orphan implementation として確認する。
