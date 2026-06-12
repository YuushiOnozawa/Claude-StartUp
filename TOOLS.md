# ツール詳細

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

---

## kizami（長期記憶）

[okamyuji/kizami](https://github.com/okamyuji/kizami) — 会話履歴をセッション終了時に自動保存し、過去の文脈を recall できる長期記憶システム。Hybrid モード（SQLite + ベクトル検索）でセットアップされる。

導入確認:

```bash
kizami list            # 保存済み会話の一覧
kizami stats           # DB 統計情報
```

### 保存タイミング

| タイミング | 説明 |
|---|---|
| SessionEnd フック | 会話終了時に自動保存 |
| `/clear` 実行時 | SessionEnd フックが発火し保存される |

---

## knowledge-rag（知識検索）

[lyonzin/knowledge-rag](https://github.com/lyonzin/knowledge-rag) — MCP サーバーとして動作する RAG ベースの知識検索システム。Ollama + llm CLI 経由でローカル LLM からも検索可能。

### 構成

| コンポーネント | 説明 |
|---|---|
| knowledge-rag | MCP サーバー（ChromaDB + BM25 ハイブリッド検索） |
| Ollama + qwen3:8b | ローカル LLM（tool calling 対応） |
| llm + llm-ollama + llm-tools-mcp | CLI から MCP 経由で検索するパイプライン |

すべて `~/.local/share/knowledge-rag/venv/` の Python venv にインストールされる。

### 動作確認

```bash
# Claude から直接 MCP ツールとして利用可能（自動登録済み）

# CLI からの検索（Ollama 経由）
~/.local/share/knowledge-rag/venv/bin/llm -m qwen3:8b -T MCP \
  "search_knowledge ツールで query='検索語' を検索し、結果を日本語で要約して"
```

### セットアップオプション

| 環境変数 | 説明 |
|---|---|
| `SKIP_OLLAMA_MODEL=1` | Ollama モデル（~1.9GB）のダウンロードをスキップ |

Ollama サーバーが起動していない場合、モデル取得はスキップされる。事前に `ollama serve` を起動してから `setup.sh` を実行すること。

### 保存タイミング

| タイミング | カテゴリ | 説明 |
|---|---|---|
| ミス検知時（UserPromptSubmit フック） | `lessons-learned` | 作業中のミスを自動記録 |
| セッション終了後（sessions → knowledge 昇格フロー） | `knowledge` | セッション記録を自動昇格 |
| 手動 | 任意 | `add_document` ツールを直接呼び出し |

---

## pCloud（Obsidian Vault アクセス）

WSL2 内から pCloud に保存した Obsidian Vault にアクセスするための FUSE マウント設定。

- `setup.sh` で rclone をインストールし `~/pcloud` マウントポイントを作成する
- OAuth 認証は対話式のため **初回のみ手動で実行**が必要（詳細: `docs/pcloud-rclone-setup.md`）

```bash
# 認証設定（初回のみ）
rclone config

# マウント
rclone mount pcloud: ~/pcloud --daemon --vfs-cache-mode writes

# アンマウント
fusermount -u ~/pcloud
```

マウント後は `~/pcloud/<Vault名>/` にファイルを書き込むだけで pCloud が自動同期し、Windows・スマホ等の Obsidian から参照できる。

> **WSL2 の注意**: apt 版 rclone (v1.60) は WSL2 で FUSE マウントが動作しないバグがある。`setup.sh` は公式インストーラ経由で v1.73+ を導入する。

---

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
