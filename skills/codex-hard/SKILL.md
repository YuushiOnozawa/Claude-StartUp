---
name: codex-hard
description: 'Codex 5体（MELCHIOR/BALTHASAR/METATRON/SANDALPHON/LELIEL）+ CASPER（Haiku）でPRレビューを行う。検出は各ペルソナが独立blind実行し、監査Codexが意味的グルーピングとペルソナ帰属を決定する。GitHubへの投稿は行わない。Trigger: "/codex-hard", "codex-hard", "Codexでハードレビュー"'
---

# CODEX-HARD スキル

## 実行前の注意

実行前に、Codex最大8回（5ペルソナ+監査）、各600秒timeoutで、最悪ケースでは約80分かかることに加え、Haiku 1〜数回（CASPER、diffサイズ依存のチャンク分割）とHaiku/Ollama 1回（CASPER結果のバッチNormalizer）が発生することをユーザーへ伝える。CASPERのHaiku呼び出し回数は固定回数と断定しない。

## 概要

Codex 5ペルソナ（MELCHIOR/BALTHASAR/METATRON/SANDALPHON/LELIEL）を逐次blind呼び出しし、
`skills/flow-common/references/casper-engine.md` の共通契約に従う CASPER engine の実行と、
監査Codexによる意味的グルーピングとペルソナ帰属の決定まで行う読み取り専用レビューである。
CASPER の呼び出し・検出・正規化・persona固定・失敗捕捉・dedup は同共通契約を参照し、結果を downstream へ渡す。
既存の`/magi-hard`（ローカルLLM）とは独立したCodexベースのレビューである。`/magi-hard` とはどちらか一方を選んで実行し、両方の実行は不要である。

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
