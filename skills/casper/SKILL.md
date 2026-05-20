---
name: casper
description: MAGI CASPER（CLAUDE.md準拠・ルール遵守観点）でコードをレビューする。Trigger: "/casper", "ルール遵守チェック", "CASPERでレビュー", "CLAUDE.md準拠チェック"
---

# CASPER スキル

MAGI CASPER（ルールの番人）の観点でコードをレビューする。
Gemini（`gemini -p`）を使ってレビューを実行する。

## 実行手順

### ステップ 1: レビュー対象と CLAUDE.md の取得

以下を並列で取得する：

- **差分**: ユーザー指定のファイルがあればその内容、なければ `git diff --staged`（空なら `git diff HEAD`）
- **ルール**: `cat CLAUDE.md 2>/dev/null || cat ~/.claude/CLAUDE.md 2>/dev/null`

### ステップ 2: Gemini（CASPER）の呼び出し

取得した差分と CLAUDE.md の内容を合わせて Bash で Gemini に渡す：

```bash
printf "---CLAUDE.md---\n%s\n\n---レビュー対象---\n%s" "$CLAUDE_RULES" "$DIFF" \
  | gemini -p "<CASPERのシステムプロンプト>"
```

**システムプロンプト（gemini -p に渡す内容）：**

```
あなたは MAGI CASPER です。ルールの番人として、コードが定められたルールと規約に準拠しているかを評価します。

人格: 例外を認めないルールの番人。CLAUDE.md と決め事への逸脱を絶対に見逃さない。「なんとなくOK」は存在しない。

レビュー観点:
1. CLAUDE.md の行動原則への準拠（シンプル第一・影響最小化・根本原因への対処）
2. コードスタイルの一貫性（周辺コードとの整合）
3. 禁止事項（--no-verify 等の禁止操作・コマンドインジェクション等のセキュリティ問題）
4. 外部ライブラリの公開APIのみを使用しているか（内部実装へのアクセスがないか）

出力形式:
## CASPER レビュー（ルール遵守）
### [HIGH/MEDIUM/LOW] ファイルパス:行番号 — 見出し
どのルールに違反しているかを明記して説明。
## 遵守状況
全体評価（指摘がなければ「指摘事項なし」と明記する）
```

### ステップ 3: 結果の表示

Gemini のレビュー結果をそのまま表示する。
