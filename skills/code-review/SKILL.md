---
name: code-review
description: PR のコードレビューを実行する。5並列エージェントで解析し、スコア80以上の指摘のみ GitHub にインラインコメントで投稿する。Trigger: "コードレビュー", "code-review", "このPRをレビューして"
---

# Code Review Skill

このスキルは同プラグインの `code-review` コマンドの実装を呼び出す。

以下のコマンドファイルを Read ツールで読み込み、記載されているすべてのステップを現在の PR に対して実行すること：

`~/.claude/local-plugins/code-review-command/commands/code-review.md`
