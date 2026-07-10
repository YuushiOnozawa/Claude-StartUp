---
name: sync-check
description: 実働環境（~/.claude/）と配布原本（~/srcs/Claude-StartUp/）の還流漏れを検知する
---

# /sync-check スキル

実働環境で追加・変更されたスキル等が配布原本に還流されていないものを検知する。

⚠ 実行前に `~/.claude/scripts/sync-check.sh` が存在することを確認してください
（初回のみ: `cp ~/srcs/Claude-StartUp/scripts/sync-check.sh ~/.claude/scripts/`）

## 基本実行

```bash
~/.claude/scripts/sync-check.sh
```

## verbose モード（同一ファイルも表示）

```bash
~/.claude/scripts/sync-check.sh --verbose
```

## 比較先の上書き

```bash
~/.claude/scripts/sync-check.sh [実働環境パス] [配布原本パス]
```

## 出力カテゴリと対処

| カテゴリ | 意味 | 対処 |
|---|---|---|
| 要還流（新規） | 実働環境にのみ存在 | ブランチ作成 → cp → PR |
| 要還流（変更） | 両側に存在するが差分あり | diff で確認 → 有益な変更のみ PR |
| 削除予定（既知） | 還流しない（対応 core で削除予定） | 対応 core の実装を待つ |
| 同一 | 差分なし（--verbose 時のみ表示） | 対応不要 |

## exit code

| code | 意味 |
|---|---|
| 0 | 還流漏れなし |
| 1 | 還流漏れあり（要還流 1件以上） |
| 2 | エラー（whitelist 欠損 / 実働環境パス欠損 等） |

## 注意

- 本スキルは手動実行専用。hooks への自動登録は行わない
- settings.json / CLAUDE.local.md 等のローカルデータは対象外
