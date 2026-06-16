# スキル一覧

このリポジトリで定義されているスキル（`/` コマンド）の説明。
スキル本体は `skills/<name>/SKILL.md`、エージェント定義は `agents/<name>.md` に置かれる。

---

## 開発フロー

| スキル | 概要 |
|--------|------|
| `/dev-flow` | 単一機能の開発サイクル（設計 → BALTHASAR レビュー → 承認 → 実装 → MAGI → PR） |
| `/epic-flow` | 大規模機能の開発。規模を評価し、単一なら `/dev-flow`、複数なら Issue 分解してループ実行 |
| `/codegen` | コード生成を **gemma4:12b**（Ollama）に委譲。Claude が仕様書を書き、ローカル LLM が実装する |
| `/commit` | Conventional Commits 形式で安全にコミット。main/master への直接コミットは拒否 |
| `/worktree` | Git worktree の管理。`new <branch>` / `done <branch>` / `list` サブコマンド |

---

## MAGI レビュー

MAGI は5体のレビューエージェント群。各体は **Ollama（ローカル LLM）優先、Haiku フォールバック** で動作する。

### モデル割り当て

| 体 | スキル | ローカル LLM | Haiku fallback | 観点 |
|----|--------|-------------|----------------|------|
| MELCHIOR | `/melchior` | `qwen2.5-coder:7b` | ○ | コード品質・バグ |
| BALTHASAR | `/balthasar` | `phi4:latest` | ○ | 設計・アーキテクチャ |
| CASPER | `/casper` | `llama3.1:8b` | ○ | CLAUDE.md ルール遵守 |
| METATRON | `/metatron` | `devstral:latest` | ○ | セキュリティ・脆弱性 |
| SANDALPHON | `/sandalphon` | `lfm2.5:8b` | ○ | デプロイ・実行環境整合性 |

### レビューパイプライン

| スキル | 体 | 用途 |
|--------|-----|------|
| `/magi-fast` | MELCHIOR→BALTHASAR→CASPER | コミット前チェック。HIGH 指摘ゼロで LGTM |
| `/magi-hard` | 5体すべて | PR レビュー。結果を GitHub インラインコメントで投稿 |
| `/pr-review` | magi-hard 呼び出し | PR レビューのエントリーポイント。HIGH/MEDIUM 指摘があれば `/pr-review-respond` と交互にループ |
| `/pr-review-respond` | — | PR レビューコメントへの対応。Haiku で second opinion、実装は `/codegen` 優先 |
| `/code-review` | 5並列エージェント | コード品質レビュー。スコア 80 以上の指摘のみ GitHub にコメント投稿 |

---

## ユーティリティ

| スキル | 概要 |
|--------|------|
| `/remember` | 知見・洞察を Obsidian knowledge/ と knowledge-rag に保存 |
| `/update-config` | `settings.json` への自動化設定（フック等）を更新 |

---

## ローカル LLM 依存関係まとめ

各スキルが要求する Ollama モデル（`ollama list` で確認）：

| モデル | 用途 | VRAM 目安 |
|--------|------|----------|
| `gemma4:12b` | codegen（コード生成） | ~8GB |
| `qwen2.5-coder:7b` | MELCHIOR（コード品質） | ~5GB |
| `phi4:latest` | BALTHASAR（設計） | ~9GB |
| `llama3.1:8b` | CASPER（ルール遵守） | ~5GB |
| `devstral:latest` | METATRON（セキュリティ） | ~14GB |
| `lfm2.5:8b` | SANDALPHON（デプロイ） | ~5GB |
| `qwen3:8b` | knowledge-rag / Obsidian index | ~5GB |

いずれも Ollama が起動していない場合は Haiku にフォールバックする（codegen のみ Haiku に委譲）。
モデルが不足している場合は `ollama pull <model>` で取得する。
