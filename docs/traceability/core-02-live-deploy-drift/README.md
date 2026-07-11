# Core 02: 実働環境で生まれた開発内容の還流経路が未定義

> 旧番号: core-05（2026-07-06 実行順に並べ替え）
> 旧核問題名: 「本番 ~/.claude とリポジトリの正が分裂している」（2026-07-07 前提変更により改名）
> フォルダ名 `core-02-live-deploy-drift` は churn 回避のため変更しない
> 前提変更の経緯: `opus-context-2026-07-07.md` / `sonnet-handoff-2026-07-07.md` 参照

## 核問題名

実働環境で生まれた開発内容の還流経路が未定義

## 用語

- **実働環境**: `~/.claude/`。開発最適化された作業環境。リポジトリと一致している必要はない（旧「本番」は廃止）
- **配布原本**: 開発リポジトリ。新規環境構築の正。実働環境の上位ではなく、還流の終着点
- **還流**: 実働環境で生まれた開発内容を配布原本へ PR として戻すこと

## 関連Fable項目

- 15: 本番 ~/.claude クローンの git 状態正常化とデプロイフロー定義
- 07（一部）: リポジトリ衛生 ← worktree 残骸・.gitignore 整合は **core-03.4 へ移管済み**

## 関連するリポジトリ目的

- 個人用 ~/.claude/ 共通設定の再現可能な展開
- 新規環境へのワンライナー展開
- 開発フローSKILL

## 問題概要

2026-07-07 確定: `~/.claude/` が配布原本と diverge していること自体は問題ではない。
実働環境は開発作業のために最適化されていればよく、根本目的は「新規マシンで同一環境を構築できること」。

真の問題は、開発内容が実働環境で生まれる（例: traceability-*, lean-ctx, compact-prep 等のスキル群が
実働環境にのみ存在し未マージ）にもかかわらず、実働環境 → 配布原本の還流経路が未定義であること。
還流されない開発内容は配布原本の網羅性を静かに劣化させ、根本目的を直接損なう。

## 分類

必須

## confidence

high

## 人間確認が必要な点（全件解決済み 2026-07-07）

- requirements.md 参照

## 重複・横断関係

- Fable 07（worktree 残骸・.gitignore 整合）→ **core-03.4 へ移管**（2026-07-07）
- core-03.1: agents/leliel.md 削除（還流検知の「既知の削除予定物」として記録）
- core-03.3: setup 完遂保証（本 core と独立した失敗モード）

## ステータス

| Document | Status | Notes |
|---|---|---|
| requirements.md | approved | 人間確認・承認済み（2026-07-07） |
| specification.md | approved | 人間確認・承認済み（2026-07-07） |
| implementation-plan.md | approved | 人間確認・承認済み（2026-07-07） |
| test-plan.md | approved | Step 8 完了（2026-07-11）。自動 10 PASS + 実環境 verify 1 PASS（TEST-02-03-11）、計 11 観点 PASS |
| design-review.md | approved | Step 7 完了（2026-07-11）。Codex レビュー・人間確認済み |
| traceability-map.md | draft | 各工程で更新 |
| traceability-audit.md | verified | Step 9 完了（2026-07-11）。Codex 二次確認・人間確認済み。要対応ゼロで verified |
