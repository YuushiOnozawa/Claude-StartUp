---
name: metatron
desc: MAGI METATRON（セキュリティ・脆弱性観点）でコードをレビューする。Trigger: "/metatron", "セキュリティレビュー", "METATRONでレビュー", "脆弱性チェックして", "Metatron"
argument-hint: "<ファイルパス または差分>"
---
# METATRON スキル

MAGI METATRON（セキュリティの番人）の観点でコードをレビューする。
Ollama `granite3.3:8b` が利用可能な場合はそちらを使い、なければ Haiku にフォールバックする。

## ペルソナ固有設定

| 項目 | 値 |
|-----|---|
| OLLAMA_MODEL | `granite3.3:8b` |
| PERSONA_NAME | `METATRON` |
| エージェント定義 | `agents/metatron.md`（repo 内）または `/home/<user>/.claude/agents/metatron.md` |

## 参照ファイル

- `skills/magi-common/references/execution-steps.md` — 共通実行手順（Read して展開する）
- `skills/magi-common/references/output-format.md` — 共通出力フォーマット
- `references/task-instruction.md` — ロール定義・ペルソナ名ヘッダー・few-shot出力例
- `references/review-criteria.md` — レビュー観点・重大度基準・守備範囲外

## 実行

`skills/magi-common/references/execution-steps.md` を Read し、
「ペルソナ固有設定」の値を当てはめて手順を実行する。
