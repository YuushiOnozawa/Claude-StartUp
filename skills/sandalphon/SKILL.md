---
name: sandalphon
desc: MAGI SANDALPHON（実行環境・デプロイ整合性観点）でコードをレビューする。Trigger: "/sandalphon", "デプロイレビュー", "SANDALPHONでレビュー", "実行環境チェックして", "Sandalphon"
argument-hint: "<ファイルパス または差分>"
---
# SANDALPHON スキル

MAGI SANDALPHON（実行環境の番人）の観点でコードをレビューする。
Ollama `phi4:latest` が利用可能な場合はそちらを使い、なければ Haiku にフォールバックする。

## ペルソナ固有設定

| 項目 | 値 |
|-----|---|
| OLLAMA_MODEL | `phi4:latest` |
| PERSONA_NAME | `SANDALPHON` |
| エージェント定義 | `agents/sandalphon.md`（repo 内）または `/home/<user>/.claude/agents/sandalphon.md` |

## 参照ファイル

- `skills/magi-common/references/execution-steps.md` — 共通実行手順（Read して展開する）
- `skills/magi-common/references/output-format.md` — 共通出力フォーマット
- `references/task-instruction.md` — ロール定義・ペルソナ名ヘッダー・few-shot出力例
- `references/review-criteria.md` — レビュー観点・重大度基準・守備範囲外

## 実行

`skills/magi-common/references/execution-steps.md` を Read し、
「ペルソナ固有設定」の値を当てはめて手順を実行する。
