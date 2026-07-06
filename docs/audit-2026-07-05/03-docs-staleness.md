# 03. ドキュメント陳腐化（SKILLS.md / DESIGN.md / README.md）

種別: 修正対応 / 深刻度: 中（ただし CASPER/CLAUDE.md 経由でレビュー挙動に影響しうる）

## 現状の不一致一覧

### SKILLS.md

| 記述 | 実態 |
|---|---|
| 「MAGI は5体」 | magi-hard は LELIEL を含む **6体**（magi-fast は3体） |
| BALTHASAR = `phi4:latest` | `gemma4:e4b-it-qat`（skills/balthasar/SKILL.md） |
| SANDALPHON = `lfm2.5:8b` | `phi4:latest`（skills/sandalphon/SKILL.md） |
| CASPER = `llama3.1:8b` + Haiku fallback ○ | **Haiku 標準**（Ollama パス不使用） |
| LELIEL の行がない | `deepseek-r1:8b` / 既存ソース影響観点 |
| `/codegen` は「gemma4:12b（Ollama）に委譲」 | **Codex Plugin（GPT-5.4）委譲、fallback は Haiku** |
| ローカルLLM依存表に gemma4:12b（codegen）等 | 02 のモデル表と同期が必要 |
| magi-hard に `--audit` 相当の記述なし | magi-fast `--audit` オプション、magi-hard/pr-review-respond の Codex 監査標準化が未記載 |
| `/dev-flow` の設計レビュー主体が BALTHASAR | Codex 優先（BALTHASAR フォールバック）に変更済み（flow-common/design-review.md） |
| 未掲載スキル | `/grill-me`, `/finished-pr`, `/self-healing`, `/self-improvement`, `/learning-aggregator`, `/intent-framed-agent`, `/leliel` |

### DESIGN.md

- 「codegen（コード生成委譲）= gemma4:12b」→ Codex 移行済み。ローカルLLM選定方針の表全体を現状化する。
- ツール間連携図に Codex（実装・監査・設計レビュー層）と lean-ctx が登場しない。
  「実装は Codex、Claude はオーケストラ」というリポジトリの中核方針が DESIGN.md に書かれていない。

### README.md

- ファイル構成表の「`local-plugins/` ローカルプラグイン群」→ ディレクトリ自体が存在しない
  （600-local-plugins.sh は skills/agents/scripts の配置確認に変質済み）。`skills/` 全体の説明に置き換える。
- 「導入されるツール」表に Ollama / MAGI モデル群 / Codex CLI+Plugin / lean-ctx / semgrep+gitleaks / mise が載っていない。

### CLAUDE.md（軽微）

- 「/codegen（Codex委譲）」は更新済みで整合。変更不要。

## 対応プラン

1. 02（モデル同期）の確定後に着手する（順序依存: 正のモデル表が先）。
2. SKILLS.md を全面改訂：
   - MAGI 表を 6体構成に更新（fast=3体 / hard=6体 の使い分けを明記、CASPER は Haiku 標準と注記）
   - Codex の役割（codegen 実装 / MAGI 監査 / 設計レビュー）を独立セクションで追加
   - 未掲載スキル7個を分類ごとに追記
   - ローカルLLM依存表を 800 のリストと一致させる
3. DESIGN.md の連携図を更新（Codex 層・lean-ctx を追加、蒸留パイプラインの SessionStart/End キュー方式を反映）。
4. README.md のファイル構成表・導入ツール表を現状化（12-manual-steps-checklist.md と同時に実施推奨）。
5. 再発防止: 「モデル・構成を変えたら SKILLS.md / DESIGN.md / setup/800 を同一 PR で更新する」を
   dev-flow の PR テンプレか AGENTS.md チェック項目に追加する。CI 突合（11）でも検出できるようにする。

## 受け入れ基準

- [ ] SKILLS.md のモデル表 = 各 SKILL.md の OLLAMA_MODEL = setup/800 のリスト、の3者が一致
- [ ] README.md に存在しないディレクトリへの言及がない
- [ ] DESIGN.md を読めば「Codex が実装・監査、Claude がオーケストラ、レビューは1スキル1ローカルLLM」が分かる

## 影響ファイル

- `SKILLS.md`, `DESIGN.md`, `README.md`
