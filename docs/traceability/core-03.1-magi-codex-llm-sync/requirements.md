# Requirements: Core 03.1 — MAGI / Codex / ローカルLLM連携の実体・参照・割当ズレ

> 人間確認済み: 2026-07-07

## 背景

MAGI、ローカルLLM、Codex の実体が、参照パス・エージェント定義・setup スクリプトと同期していない。
開発フローのレビューゲートが期待通り動くかに直結する。

**前提（core-01 REQ-01-02 より）**: WindowsホストOllama（`OLLAMA_HOST`）が標準構成。
WSL2内へのモデルpullは不要。スキル側のモデル名は「WindowsホストOllamaで必要なモデル」の文書として機能する。

関連Fable項目: 01, 02, 06, 08（03, 05 は他 core へ移管）

## 問題

| ID | 問題 |
|---|---|
| PROB-03.1-01 | 全ペルソナの SKILL.md に削除済み `agents/xxx.md` への参照が残っており、PR #203 の完遂が未完（balthasar, casper, leliel, melchior, metatron, sandalphon） |
| PROB-03.1-02 | `agents/leliel.md` が `model: haiku` 固定で定義されており、他の MAGI 体（Ollama-first）と設計が異なる。magi-hard は `/leliel` スキル経由のため実際には使われないが `Agent(subagent_type="leliel")` でスキルフローをバイパスできる状態 |
| PROB-03.1-03 | magi-fast/magi-hard が `bash scripts/magi-diff-filter.sh`・`bash scripts/magi-impact-context.sh` と相対パス参照しており、他プロジェクトcwdから実行すると「差分なし」と誤判定する |
| PROB-03.1-04 | `setup/800-ollama-models.sh` が WSL2内にモデルをpullしているが、WindowsホストOllama標準構成（REQ-01-02）では WSL2内pullは不要であり誤った処理 |
| PROB-03.1-05 | `magi-common/references/execution-steps.md` が `$AGENT_PATH`（`agents/xxx.md`）を前提とした Haiku fallback 手順を記述しており、agents/ 削除後の構成と矛盾している |

## 確定した要求

| # | 要求 | 根拠 |
|---|---|---|
| REQ-03.1-01 | 全ペルソナ（balthasar, casper, leliel, melchior, metatron, sandalphon）の SKILL.md から `agents/xxx.md` 参照行を削除する | PROB-03.1-01 / PR #203 完遂 / 2026-07-07 確定 |
| REQ-03.1-02 | `agents/leliel.md` を削除する。Haiku fallback は LELIEL スキル内で直接 Haiku を呼ぶ形にする | PROB-03.1-02 / 2026-07-07 確定（core-02 Step 3 で発覚） |
| REQ-03.1-03 | `magi-common/references/execution-steps.md` の `$AGENT_PATH` / `agents/` 参照を削除し、Haiku fallback 手順を agents/ 非依存に更新する | PROB-03.1-05 / PR #203 完遂 / 2026-07-07 確定 |
| REQ-03.1-04 | magi-fast/magi-hard のスクリプト参照を相対パス（`bash scripts/...`）から絶対パス（`bash "$HOME/.claude/scripts/..."`）に修正する | PROB-03.1-03 / 2026-07-07 確定 |
| REQ-03.1-05 | `setup/800-ollama-models.sh` を削除または無効化する。WindowsホストOllamaが標準構成のためWSL2内pullは不要 | PROB-03.1-04 / REQ-01-02 / 2026-07-07 確定 |
| REQ-03.1-06 | SKILL.md の `OLLAMA_MODEL` 記載は「WindowsホストOllamaに必要なモデル」の文書として維持する。LELIEL は `deepseek-r1:8b`、METATRON は `devstral:latest`（継続）、他は現状を正とする。**注記（2026-07-16、監査 A-003）**: 具体モデル名は PR #282（VRAM 制約適合）で LELIEL=`llama3.1:8b`・METATRON=`granite3.3:8b` に変更済み。README「外部先行変更（2026-07-16 記録）」および改訂 SPEC-03.1-06 を正とする | 2026-07-07 確定 / 注記 2026-07-16 承認 |
| REQ-03.1-07 | Codex CLI は `setup/850-codex.sh` で「導入確認のみ」を維持する。バージョン固定はしない。動作確認済みバージョンを README に記載する | 2026-07-07 確定 |

## 受け入れ条件

- 全ペルソナの SKILL.md に `agents/xxx.md` の記述がない
- `agents/` ディレクトリに `leliel.md` が存在しない（リポジトリ・実働環境とも）
- `execution-steps.md` に `$AGENT_PATH` / `agents/` への参照がない
- 他プロジェクトcwd（例: `~/srcs/other-project/`）で `/magi-fast` を実行しても差分検出・フィルタ・モデル呼び出しが完走する
- `setup/800-ollama-models.sh` が存在しないか、明示的に無効化されている
- `setup.sh` が `800-ollama-models.sh` を呼ばない（または無効化を認識している）

## 対象外

- OLLAMA_HOST 疎通確認の実装 → **core-03.3**（setup readiness）
- SKILLS.md / DESIGN.md / README.md のドキュメント陳腐化修正 → **core-03.4**
- Codex CLI 自動インストールの実装 → **core-03.3**
- METATRON の devstral 代替検討 → devstral 継続決定、必要なら別 Issue
- knowledge-distill / error-detector 関連 → **core-03.2**
- agents/ を配備するかどうかの deploy.sh 設計 → **core-02**

## 依存関係

- core-01 REQ-01-02（WindowsホストOllama標準構成）→ approved ✅（setup/800-ollama-models.sh 削除の根拠）
- core-02 REQ-02-02（内容物ホワイトリスト）→ agents/ 配備設計と連動
- core-03.1 完了が core-02 の deploy.sh 実装前提（agents/ から leliel.md を除いた状態で配備する）

## 人間確認事項（全件解決済み）

| 確認事項 | 決定 | 日付 |
|---|---|---|
| agents/ 参照の整理方針 | PR #203 完遂（全削除） | 2026-07-07 |
| METATRON devstral 継続可否 | 継続。代替は別 Issue | 2026-07-07 |
| Codex CLI バージョン固定 | 固定しない。README に記載のみ | 2026-07-07 |
| setup/800-ollama-models.sh の扱い | 削除または無効化（WindowsホストOllama前提で不要） | 2026-07-07 |
| LELIEL の agents/leliel.md | 削除（haiku 固定で設計不整合） | 2026-07-07（core-02 Step 3 で発覚） |
