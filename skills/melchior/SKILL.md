---
name: melchior
desc: MAGI MELCHIOR（コード品質・バグ観点）でコードをレビューする。Trigger: "/melchior", "コード品質レビュー", "MELCHIORでレビュー", "バグチェックして", "Melchior"
argument-hint: "<ファイルパス または差分>"
---
# MELCHIOR スキル

MAGI MELCHIOR（科学者）の観点でコードをレビューする。
Ollama `qwen2.5-coder:7b` が利用可能な場合はそちらを使い、なければ Haiku にフォールバックする。

## ペルソナ固有設定

| 項目 | 値 |
|-----|---|
| OLLAMA_MODEL | `qwen2.5-coder:7b` |
| PERSONA_NAME | `MELCHIOR` |
| PERSONA_FILE | `skills/melchior/references/persona.md` |

## 参照ファイル

- `skills/magi-common/references/execution-steps.md` — 共通実行手順（Read して展開する）
- `skills/magi-common/references/output-format.md` — 共通出力フォーマット
- `references/persona.md` — ペルソナ定義（人格・制約）
- `references/task-instruction.md` — ペルソナ名ヘッダー・few-shot出力例
- `references/review-criteria.md` — レビュー観点・重大度基準・守備範囲外

## 実行

`skills/magi-common/references/execution-steps.md` を Read し、
「ペルソナ固有設定」の値を当てはめて手順を実行する。
