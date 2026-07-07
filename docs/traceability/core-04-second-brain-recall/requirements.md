# Requirements: Core 04 — 第二の脳・プロジェクト横断想起の運用仕様化

> 人間確認済み: 2026-07-07

## 背景

長期記憶を「保存できる」だけでなく、Obsidian inbox からの調査還流、経験カード化、
auto-recall による横断想起へ進めるための運用仕様が未確定である。

関連リポジトリ目的: 会話ログ蒸留による長期記憶、Obsidianを介した知識還流、プロジェクト横断の想起

関連Fable項目: 13, 16, 17（13 は core-03.2 とも重複）

## 適用前提（他 core で確定済み）

- REQ-03.2-03: 記録層は rclone なしで完結。pCloud/Obsidian は配送層として分離（core-03.2 担当）
- Fable 13 の「記録層と配送層の分離・疎結合化」は core-03.2 が primary。core-04 は Obsidian inbox ワークフローと横断想起の詳細運用設計を担当

## 問題

| ID | 問題 |
|---|---|
| PROB-04-01 | Obsidian inbox からの調査・knowledge 還流フロー（`/inbox` スキル）が未実装。inbox の URL・メモを起点に Claude が調査し knowledge へ還流する手順がない |
| PROB-04-02 | 経験カードの形式が未定義。蒸留時に「状況・やったこと・結果・判断理由・技術タグ・outcome」を含む構造化カードが生成されない |
| PROB-04-03 | `store/`（蒸留済み）・`vault/`（Obsidian 取込用）・inbox 台帳の責務が未定義。transcript の切り捨て（`.[0:4000]`）や分離設計が未実装 |
| PROB-04-04 | プロジェクト横断での経験カード想起（auto-recall）が未実装。発火条件・トークン上限・タイムアウトが未定義 |

## 確定した要求

| # | 要求 | 根拠 |
|---|---|---|
| REQ-04-01 | `/inbox` スキルを実装し、Obsidian inbox の URL・メモから調査して knowledge へ還流する。人間領域ノート（Obsidian ノート本体）を Claude が直接書き換えない。v1 は手動実行のみ（SessionStart 通知は v2 以降） | PROB-04-01 / Fable 16 / 2026-07-07 確定 |
| REQ-04-02 | 経験カードの形式を定義する（状況・やったこと・結果・判断理由・技術タグ・outcome を含む）。日英両方出力を要求に含める。運用方針（日英比率・index-en/ 活用）は A/B 評価後に spec で確定する | PROB-04-02 / Fable 13, 17 / 2026-07-07 確定 |
| REQ-04-03 | `store/`（蒸留済み知識）・`vault/`（Obsidian 取込用）・`_inbox-ledger.md`（処理台帳）の責務を定義する。同一メモの二重処理を台帳で防ぐ | PROB-04-03 / Fable 13 / 2026-07-07 確定 |
| REQ-04-04 | auto-recall の設計（発火条件・検索件数・トークン上限・タイムアウト・既出抑止）を spec で定義する。実装は蒸留カード品質を一定期間評価後に判断する | PROB-04-04 / Fable 17 / 2026-07-07 確定 |

## 受け入れ条件

- `/inbox` 実行で inbox の URL・メモが調査され、結果が knowledge へ還流される
- 同一メモが二重処理されない（`_inbox-ledger.md` で追跡）
- 人間領域ノート（Obsidian ノート本体）を Claude が直接書き換えない
- 蒸留時に経験カード形式（状況・やったこと・結果・判断理由・技術タグ・outcome）に従ったカードが生成される
- `store/`・`vault/` の責務と writer が spec に記載されている
- auto-recall の設計仕様が spec に記載されている（実装条件も記載。実装判断はその後）

## 対象外

- auto-recall の実装（蒸留カード品質評価後に判断。requirements では設計・仕様化まで）
- index-en/ の運用方針・比率（A/B 評価後に確定。requirements では日英出力を要求に含めるのみ）
- SessionStart での inbox 未処理通知（v2 以降）
- Obsidian からの取込（inbox → store への一方向が primary。逆方向は将来検討）
- pCloud / Obsidian の初期シード手順（spec 以降で詳細化。core-03.2 REQ-03.2-03 で配送層として分離済み）

## 依存関係

- core-03.2 REQ-03.2-03（記録層は rclone なしで完結）→ approved ✅（配送層分離の前提）
- core-03.2 REQ-03.2-01（SessionEnd は queue push のみ）→ approved ✅（蒸留フローの前提）
- knowledge-rag（現状 API 登録継続）→ approved ✅（`search_knowledge` での想起の前提）

## 人間確認事項（全件解決済み）

| 確認事項 | 決定 | 日付 |
|---|---|---|
| /inbox v1 スコープ | 手動実行のみ。SessionStart 通知は v2 以降 | 2026-07-07 |
| auto-recall 導入タイミング | 設計のみ先行確定。実装は蒸留カード品質評価後に判断 | 2026-07-07 |
| index-en/ 方式 | A/B 評価後に確定。日英両方出力を要求に含め、運用方針は spec 以降 | 2026-07-07 |
