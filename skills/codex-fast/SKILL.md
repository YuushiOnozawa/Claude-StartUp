---
name: codex-fast
description: 'Codex 2体（MELCHIOR/BALTHASAR）+ CASPER（Haiku）の軽量版でPRレビューを行う。CASPER findingは全件block固定。GitHubへの投稿は行わない。Trigger: "/codex-fast", "codex-fast", "Codexでファストレビュー"'
---

# CODEX-FAST スキル

## 実行前の注意

実行前に、Codex 3回（MELCHIOR/BALTHASAR/監査）に加え、Haiku 1〜数回（CASPER、diffサイズ依存のチャンク分割）とHaiku/Ollama 1回（CASPER結果のバッチNormalizer）が発生し、所要時間はdiffサイズにより変動することをユーザーへ伝える。CASPERのHaiku呼び出し回数は固定回数と断定しない。

## 概要

`/codex-hard`の軽量版として、MELCHIOR/BALTHASARのCodex blind呼び出し、既存`/casper`スキル（Haiku）、監査、決定的mergeを行う読み取り専用レビューである。
CASPERの結果はバッチNormalizerを経て統合し、hardと同じレビュー結果契約へまとめる。

## 前提

- Codex companionが利用可能であること（`~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs`）。
- カレントディレクトリがGitリポジトリであること。

## ステップ 1: 参照手順の読み込みと実行

`skills/dev-flow-fast/references/codex-review-fast.md`をReadツールで読み込み、記載の手順に従って実行する。

## CASPERのgate

CASPER findingは全件`gate=block`固定とし、CASPER findingに対する追加のCodex gate判定は行わない。

## 出力

ユーザーには、次の結果を表示する。

- `pipeline_status`（`complete` / `incomplete`）。
- ペルソナ別および`canonical_persona`別の`gate`集計。
- `manual_review`（未監査・要人手確認）セクション。

GitHubへの投稿、PRコメント、コミット、ファイル編集は一切行わない。
