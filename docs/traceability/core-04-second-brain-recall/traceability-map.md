# Traceability Map: Core 04 — 第二の脳・プロジェクト横断想起

> requirements approved: 2026-07-07

## Step 3 — 問題 → 要求

| PROB ID | 問題 | 対応 REQ | ステータス |
|---|---|---|---|
| PROB-04-01 | Obsidian inbox からの調査・knowledge 還流フロー（/inbox スキル）が未実装 | REQ-04-01 | approved |
| PROB-04-02 | 経験カードの形式（状況・やったこと・結果・判断理由・技術タグ・outcome）が未定義 | REQ-04-02 | approved |
| PROB-04-03 | store/・vault/・_inbox-ledger.md の責務が未定義。transcript の切り捨て・分離設計が未実装 | REQ-04-03 | approved |
| PROB-04-04 | auto-recall の発火条件・トークン上限・タイムアウトが未定義。実装も未 | REQ-04-04 | approved |

## 要求一覧

| REQ ID | 要求概要 | Fable | ステータス |
|---|---|---|---|
| REQ-04-01 | /inbox スキル実装。inbox の URL・メモから調査して knowledge へ還流。人間ノート直接書き換え禁止。v1 は手動実行のみ | 16 | approved |
| REQ-04-02 | 経験カード形式を定義（状況・やったこと・結果・判断理由・技術タグ・outcome）。日英両方出力を要求に含める。運用方針は spec 以降 | 13, 17 | approved |
| REQ-04-03 | store/・vault/・_inbox-ledger.md の責務を定義。同一メモの二重処理を台帳で防ぐ | 13 | approved |
| REQ-04-04 | auto-recall の設計（発火条件・検索件数・トークン上限・タイムアウト・既出抑止）を spec で定義。実装は品質評価後に判断 | 17 | approved |

## 依存・横断関係

- core-03.2 REQ-03.2-03（記録層は rclone なしで完結）→ approved ✅（配送層分離の前提）
- core-03.2 REQ-03.2-01（SessionEnd は queue push のみ）→ approved ✅（蒸留フローの前提）
- Fable 13 → core-03.2 が記録層・配送層分離の primary。core-04 は Obsidian inbox ワークフローの primary
- Fable 16, 17 → core-04 が primary

## 注意

要求・仕様・実装計画・テスト設計の各段階で更新する。
auto-recall（REQ-04-04）は spec での設計を先行させ、実装は蒸留カード品質評価後に判断する。
