---
name: traceability-flow
description: トレーサビリティ駆動開発の進行役。全体ボードから各核問題の現在地を判定し、次に実行すべき traceability-* スキルを提案・起動する。Trigger: "/traceability-flow", "トレーサビリティ", "核問題の続き", "次の核問題", "トレサビ進めて"
argument-hint: "<core-XX（省略可）>"
---

# TRACEABILITY-FLOW

トレーサビリティ駆動開発（Step 1〜9）の進行役。各 Step の実体は個別スキルに委譲する。

## Step とスキルの対応

| Step | スキル | 出力 |
|---|---|---|
| 1 分類 | `/traceability-classify` | docs/planning/*.md |
| 2 フォルダ生成 | `/traceability-init-docs` | core-XX/ 一式（draft） |
| 3 要求定義 | `/traceability-requirements` | requirements.md |
| 4 仕様化 | `/traceability-spec` | specification.md |
| 5 実装項目策定 | `/traceability-impl-plan` | implementation-plan.md |
| 6 実装 | `/traceability-implement` | コード差分 + map 更新 |
| 7 設計レビュー | `/traceability-design-review` | design-review.md |
| 8 テスト | `/traceability-test` | test-plan.md + テスト |
| 9 監査 | `/traceability-audit` | traceability-audit.md |
| — ボード更新 | `/traceability-board-update` | docs/traceability/README.md |

> モデル運用: 全 Step で メインセッションは Sonnet のままでよい。高負荷な統合・検証は
> Step 1 = Phase B 外出し（Codex 優先 / Opus subagent）、Step 9 = Codex 二次確認として
> 低クォータで実行する設計（5h ウィンドウ対策）。セッションごとモデル切替はしない。

## 手順

1. `skills/traceability-common/references/rules.md`（repo 内。なければ `~/.claude/skills/traceability-common/references/rules.md`） を Read する
2. `docs/traceability/README.md`（全体ボード）を Read。無ければ `/traceability-board-update` を先に実行
3. 引数の core-XX（無指定なら全核問題）について現在地を判定する:
   - requirements が draft → 次は Step 3 の人間確認（または再生成）
   - requirements が approved で specification が draft → 次は Step 4
   - 以降同様に「approved になった直後の Step」を次候補とする
   - blocked は理由を表示して飛ばす
4. 次のアクションを 1〜3 件提示し、AskUserQuestion で選ばせて該当スキルを実行する
5. 実行後、ボードの更新漏れがあれば `/traceability-board-update` を実行する

## 注意

- 前工程が approved でない Step の実行は提案しない（draft の上に積まない）
- 分類（必須/推奨/将来拡張/要確認）と依存関係を考慮し、必須 × 依存元を優先提案する
