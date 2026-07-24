---
name: leliel
desc: MAGI LELIEL（既存ソース影響観点）でコードをレビューする。Trigger: "/leliel", "影響観点でレビュー", "LELIELでレビュー"
argument-hint: "<ファイルパス または差分>"
---
# LELIEL スキル

MAGI LELIEL（影の守護者）の観点でコードをレビューする。
変更が既存コードの呼び出し元に与える実際の影響をコールグラフ証拠で実証する。
Ollama `deepseek-r1:8b` が利用可能な場合はそちらを使い、なければ Haiku にフォールバックする。

## ペルソナ固有設定

| 項目 | 値 |
|-----|---|
| OLLAMA_MODEL | `deepseek-r1:8b` |
| PERSONA_NAME | `LELIEL` |
| エージェント定義 | `agents/leliel.md`（repo 内）または `/home/<user>/.claude/agents/leliel.md` |

## 参照ファイル

- `skills/magi-common/references/execution-steps.md` — 共通実行手順（Read して展開する）
- `skills/magi-common/references/output-format.md` — 共通出力フォーマット
- `references/task-instruction.md` — ロール定義・ペルソナ名ヘッダー・few-shot出力例
- `references/review-criteria.md` — レビュー観点・重大度基準・守備範囲外

## 実行

`skills/magi-common/references/execution-steps.md` を Read し、
「ペルソナ固有設定」の値を当てはめて手順を実行する。
