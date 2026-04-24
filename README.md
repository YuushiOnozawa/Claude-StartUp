# Claude Code Harness

個人用 `~/.claude/` 共通設定。`setup.sh` で新マシンに展開する。

## セットアップ

### 方式 A: ワンライナー（新規マシン推奨）

```bash
curl -fsSL https://raw.githubusercontent.com/YuushiOnozawa/Claude-StartUp/main/setup.sh \
  | bash -s -- https://github.com/YuushiOnozawa/Claude-StartUp.git
```

`~/.claude/` 展開・依存ツール確認・パッケージの自動インストール（commitlint, RTK, kizami, knowledge-rag pipeline）を一括実行する。

### 方式 B: ローカル clone 済みの場合

```bash
bash setup.sh <repo-url>
```

依存ツールの確認と clone を自動処理する。未導入のパッケージは自動インストールを試みる。

### 導入されるツール

| ツール | 用途 |
|--------|------|
| [RTK](#rtk（rust-token-killer）) | Bash 出力圧縮によるトークン削減 |
| [kizami](#kizami（長期記憶）) | 会話ベースの長期記憶 |
| [knowledge-rag](#knowledge-rag（知識検索）) | RAG ベースのドキュメント検索 |

## ファイル構成

| パス | 用途 |
|------|------|
| `CLAUDE.md` | Claude Code グローバル動作原則 |
| `settings.json` | パーミッション設定 |
| `setup.sh` | 新マシン展開スクリプト |
| `skills/commit/` | `/commit` スキル |
| `agents/` | グローバルサブエージェント定義 |
| `memory/` | クロスセッション知識（自動管理） |

## RTK（Rust Token Killer）

[rtk-ai/rtk](https://github.com/rtk-ai/rtk) — PreToolUse hook で Bash コマンドを透過的に書き換え、出力を圧縮してトークン消費を 60〜90% 削減する Rust 製 CLI。

導入確認:

```bash
rtk --version          # rtk X.Y.Z が表示されれば OK
rtk gain               # セッションのトークン削減量
rtk gain --history     # 書き換えられたコマンド履歴
```

### PATH 永続化の挙動

`setup.sh` は `~/.local/bin` が PATH に無ければ、`$SHELL` に応じた rc ファイル（`zshrc` / `bashrc` / `profile`）1 本にマーカー付きで 3 行だけ追記する。次回シェル起動から恒久有効。不要な場合は該当 rc の `# Claude-StartUp: local bin (RTK 等)` ブロックを手動削除する。

### 再セットアップ時の注意（鶏卵問題）

既に Claude Code が起動中のセッションからハーネスを再展開したい場合は、**方式 A（ワンライナー）ではなく 方式 B（`bash setup.sh`）を使う**。`settings.json` の `Bash(curl * | sh)` deny ルールが先に効くため、方式 A は Claude 経由ではブロックされる。新規マシンでの初回セットアップは deny ルールが展開前なので方式 A で問題ない。

## kizami（長期記憶）

[okamyuji/kizami](https://github.com/okamyuji/kizami) — 会話履歴をセッション終了時に自動保存し、過去の文脈を recall できる長期記憶システム。Hybrid モード（SQLite + ベクトル検索）でセットアップされる。

導入確認:

```bash
kizami list            # 保存済み会話の一覧
kizami stats           # DB 統計情報
```

## knowledge-rag（知識検索）

[lyonzin/knowledge-rag](https://github.com/lyonzin/knowledge-rag) — MCP サーバーとして動作する RAG ベースの知識検索システム。Ollama + llm CLI 経由でローカル LLM からも検索可能。

### 構成

| コンポーネント | 説明 |
|---|---|
| knowledge-rag | MCP サーバー（ChromaDB + BM25 ハイブリッド検索） |
| Ollama + qwen2.5:3b | ローカル LLM（tool calling 対応） |
| llm + llm-ollama + llm-tools-mcp | CLI から MCP 経由で検索するパイプライン |

すべて `~/.local/share/knowledge-rag/venv/` の Python venv にインストールされる。

### 動作確認

```bash
# Claude から直接 MCP ツールとして利用可能（自動登録済み）

# CLI からの検索（Ollama 経由）
~/.local/share/knowledge-rag/venv/bin/llm -m qwen2.5:3b -T MCP \
  "search_knowledge ツールで query='検索語' を検索し、結果を日本語で要約して"
```

### セットアップオプション

| 環境変数 | 説明 |
|---|---|
| `SKIP_OLLAMA_MODEL=1` | Ollama モデル（~1.9GB）のダウンロードをスキップ |

Ollama サーバーが起動していない場合、モデル取得はスキップされる。事前に `ollama serve` を起動してから `setup.sh` を実行すること。

## 外部ツールが書き込むローカル差分の扱い

各ツールの init / setup コマンドは環境ごとにファイルを書き換えるが、いずれも **ローカル状態** のためリポジトリにはコミットしない（`git diff` に残っても無視してよい）。

| 書き換え対象 | RTK | kizami | knowledge-rag |
|---|---|---|---|
| `settings.json`（hook 追加） | ○ | ○ | - |
| `CLAUDE.md`（import 追記） | ○ | - | - |
| ツール専用定義ファイルの生成（`.gitignore` 対象） | ○ | - | - |
| DB・設定ファイルの初期化 | - | ○ | - |
| `~/.llm-tools-mcp/mcp.json` | - | - | ○ |
| venv（`~/.local/share/knowledge-rag/venv/`） | - | - | ○ |

## Opus 4.6 の挙動調整

`settings.json` で `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` を設定し、adaptive thinking を無効化している。`effortLevel: high` と adaptive thinking の併用で CLAUDE.md ルールやスキル定義が無視される挙動（[claude-code#23936](https://github.com/anthropics/claude-code/issues/23936)）の回避が目的。

不具合を感じる場合は、`@2.1.98` などの安定版にダウングレードすることも検討する:

```bash
npm install -g @anthropic-ai/claude-code@2.1.98
```

ただしバージョン固定は `setup.sh` には組み込まない（更新を逃す副作用が大きいため、個人判断で実施する）。

## Git 管理外

`.gitignore` 参照。認証情報・会話履歴・マシン固有データ・RTK 生成物は除外済み。
