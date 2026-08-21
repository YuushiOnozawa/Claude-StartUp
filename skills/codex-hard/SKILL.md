---
name: codex-hard
description: 'Codex 5体（MELCHIOR/BALTHASAR/METATRON/SANDALPHON/LELIEL）+ CASPER（Haiku）でPRレビューを行う。検出は各ペルソナが独立blind実行し、監査Codexが意味的グルーピングとペルソナ帰属を決定する。GitHubへの投稿は行わない。Trigger: "/codex-hard", "codex-hard", "Codexでハードレビュー"'
---

# CODEX-HARD スキル

## 実行前の注意

実行前に、Codex最大6回（5ペルソナ+監査）、各600秒timeoutで、最悪ケースでは約60分かかることに加え、Haiku 1〜数回（CASPER、diffサイズ依存のチャンク分割）とHaiku/Ollama 1回（CASPER結果のバッチNormalizer）が発生することをユーザーへ伝える。CASPERのHaiku呼び出し回数は固定回数と断定しない。

## 概要

Codex 5ペルソナ（MELCHIOR/BALTHASAR/METATRON/SANDALPHON/LELIEL）を逐次blind呼び出しし、既存`/casper`スキル（Haiku）の実行と監査Codexによる意味的グルーピングとペルソナ帰属の決定まで行う読み取り専用レビューである。CASPERの結果はバッチNormalizerを経て統合する。
既存の`/magi-hard`（ローカルLLM）とは別の独立したCodexベースのレビューであり、必要に応じて両方を実行してよい。

## 前提

- Codex companionが利用可能であること（`~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs`）。
- カレントディレクトリがGitリポジトリであること。

## ステップ 1: 参照手順の読み込みと実行

`skills/dev-flow-fast/references/codex-review-hard.md`をReadツールで読み込み、記載の手順に従って実行する。

## 出力

ユーザーには、次の結果を表示する。

- `pipeline_status`（`complete` / `incomplete`）。
- ペルソナ別および`canonical_persona`別の`gate`集計。
- `manual_review`（未監査・要人手確認）セクション。

GitHubへの投稿、PRコメント、コミット、ファイル編集は一切行わない。
