# Requirements: Core 03.2 — hooks / knowledge-distill / 知識ストアの二重化・欠落・密結合

> 人間確認済み: 2026-07-07

## 背景

hooks と knowledge-distill に、二重登録、配備漏れ、pCloud/rclone mount への密結合がある。
長期記憶の品質、重複登録、トークン消費、再現可能性に影響する。

関連リポジトリ目的: 会話ログ蒸留による長期記憶、Token削減、個人用 ~/.claude/ 共通設定の再現可能な展開

関連Fable項目: 04, 05, 13（05 は core-03.3 とも重複、13 は core-04 とも重複）

## 問題

| ID | 問題 |
|---|---|
| PROB-03.2-01 | `setup/410-hooks-distill.sh` が SessionEnd に `knowledge-distill.sh` を直接追加登録し、`settings.json` のキュー方式（SessionEnd=session-end-queue.sh）と競合する。実測で二重蒸留が発生している |
| PROB-03.2-02 | `setup/410` のログ出力先（`hooks/knowledge-distill.log`）と `settings.json` のログパス（`hooks/logs/knowledge-distill.log`）が不一致。logs の所在が散在している |
| PROB-03.2-03 | `setup/410, 411, 412, 700` が `settings.json` を動的に書き換えているが、これはキュー方式と競合しない限り許容する設計（Claude Code 自体も settings.json を自動追記するため）。setup の冪等性・競合排除は spec 以降の設計事項として扱う |
| PROB-03.2-04 | `hooks/knowledge-distill.sh`, `knowledge-prune.sh`, `knowledge-auto-promote.sh`, `skills/remember/SKILL.md`, `scripts/generate-obsidian-index.sh` 等が `~/pcloud/obsidian` mount に依存し、rclone 未起動時に失敗する |
| PROB-03.2-05 | `settings.json` の PostToolUse が参照する `error-detector.sh` が新規環境の `hooks/` に存在せず、自動エラー検知が無音で無効になる |
| PROB-03.2-06 | compact 強化フック群（compact-prep skill + 復旧 hook + 閾値通知 / PR #267）が jq 動的注入で先行導入済み。hook 登録二重化の新インスタンスだが、Step 9（audit）で orphan implementation として確認する（独立 REQ なし） |

## 確定した要求

| # | 要求 | 根拠 |
|---|---|---|
| REQ-03.2-01 | SessionEnd hook は queue push のみとし、SessionStart で drain する。SessionEnd への `knowledge-distill.sh` 直接実行は `settings.json` にも setup にも存在しない | PROB-03.2-01 / Fable 04 / 2026-07-07 確定 |
| REQ-03.2-02 | hook ログ出力先を `~/.claude/hooks/logs/` 配下に統一する（`setup/410` の `knowledge-distill.log` パスを `hooks/logs/knowledge-distill.log` に修正） | PROB-03.2-02 / Fable 04 / 2026-07-07 確定 |
| REQ-03.2-03 | 記録層（蒸留処理・knowledge-rag 登録）は rclone mount なしで完結する。pCloud/Obsidian への同期は配送層として分離し、記録層から直接 mountpoint を参照しない | PROB-03.2-04 / Fable 04, 13 / 2026-07-07 確定 |
| REQ-03.2-04 | `error-detector.sh` を `hooks/` に配備し、PostToolUse で実行可能な状態にする。新規環境の setup 完了時点で `~/.claude/hooks/error-detector.sh` が存在する | PROB-03.2-05 / Fable 05 / 2026-07-07 確定 |

## 受け入れ条件

- 1 セッション終了・次セッション開始で、同一 transcript が一度だけ蒸留・RAG 登録される（重複なし）
- `settings.json` の SessionEnd hook に `knowledge-distill.sh` の直接実行が存在しない
- `settings.json` が参照する hook スクリプトが `~/.claude/hooks/` に存在し、実行可能である（`error-detector.sh` 含む）
- rclone mount なしで蒸留・knowledge-rag 登録・自動昇格が完走する
- hook のログが `~/.claude/hooks/logs/` 配下に統一されている

## 対象外

- settings.json の動的注入廃止（Claude Code 自体も自動追記するため。setup の冪等性・競合排除は spec 設計事項）
- knowledge-rag 登録の watch 一本化（現状 API 登録を継続。spec 以降で watch 信頼性確認後に判断）
- compact 強化フック群の requirements 取り込み（外部先行変更として audit のみで管理）
- pCloud / Obsidian の初期シード手順 → **core-04**
- 知識ストアの疎結合化の詳細運用設計（Fable 13 → **core-04** が主担当）
- setup verify / doctor への error-detector 組み込み → **core-03.3**（setup readiness）
- SessionEnd/Start のフロー詳細実装 → **spec 以降**

## 依存関係

- core-02 REQ-02-05（settings.json は還流・配備対象外）→ approved ✅（settings.json が runtime 文書である前提の根拠）
- core-01 REQ-01-03（pCloud は最終集約点）→ approved ✅（記録層分離の方向性と整合）
- core-03.3（OLLAMA_HOST 疎通確認・setup readiness）→ error-detector の verify 組み込みは core-03.3 が扱う

## 人間確認事項（全件解決済み）

| 確認事項 | 決定 | 日付 |
|---|---|---|
| settings.json の正をリポジトリ直書きにするか | 動的注入継続。setup の冪等性・競合排除は spec 設計事項。独立 REQ なし | 2026-07-07 |
| knowledge-rag watch 信頼性・API 登録廃止可否 | 現状（API 登録）継続。watch は spec 以降で信頼性確認後に判断 | 2026-07-07 |
| compact 強化フック群を本 core 要求範囲に含めるか | 含めない。Step 9（audit）で orphan implementation として確認 | 2026-07-07 |
| 既存 pCloud/Obsidian データの初期シード手順 | core-04 に委ねる | 2026-07-07 |
