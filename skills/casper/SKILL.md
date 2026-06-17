---
name: casper
desc: MAGI CASPER（CLAUDE.md準拠・ルール遵守観点）でコードをレビューする。Trigger: "/casper", "ルール遵守チェック", "CASPERでレビュー", "CLAUDE.md準拠チェック"
argument-hint: "<ファイルパス または差分>"
---
# CASPER スキル

MAGI CASPER（ルールの番人）の観点でコードをレビューする。
CLAUDE.md 準拠チェックは Claude 自身が判定するほうが精度が高いため、Claude Haiku を使用する。

## ペルソナ固有設定

| 項目 | 値 |
|-----|---|
| PERSONA_NAME | `CASPER` |
| エージェント定義 | `agents/casper.md`（repo 内）または `/home/<user>/.claude/agents/casper.md` |
| CLAUDE_RULES 取得 | あり（CASPER 専用） |

## 参照ファイル

- `skills/magi-common/references/execution-steps.md` — 共通実行手順（Read して展開する）
- `skills/magi-common/references/output-format.md` — 共通出力フォーマット
- `references/task-instruction.md` — ロール定義・ペルソナ名ヘッダー・few-shot出力例
- `references/review-criteria.md` — レビュー観点・重大度基準・守備範囲外

## 実行

`skills/magi-common/references/execution-steps.md` を Read し、
「ペルソナ固有設定」の値を当てはめて手順を実行する。
CASPER 専用手順（`$CLAUDE_RULES` 取得・プロンプト末尾への CLAUDE.md 追加）は
execution-steps.md の「CASPER のみ」注記に従って実行する。

**CASPER は Ollama パスを使用しない。**
execution-steps.md のステップ 2 で Ollama チェックをスキップし、
直接「Ollama が使えない場合（Haiku パス）」を実行する。
フォールバック確認ダイアログも不要（CASPER では Haiku を標準モデルとして指定しているため）。
