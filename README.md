# Claude Code Harness

個人用 `~/.claude/` 共通設定。`setup.sh` + `setup/` モジュール群で新マシンに展開する。

## セットアップ

### 前提: Claude Code のインストール

```bash
# バージョン固定インストール（推奨）
npm install -g @anthropic-ai/claude-code@2.1.98

# 最新版
npm install -g @anthropic-ai/claude-code
```

インストール後、`claude` コマンドで認証まで完了させてから次のステップへ進む。

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
| [RTK](TOOLS.md#rtkrust-token-killer) | Bash 出力圧縮によるトークン削減 |
| [kizami](TOOLS.md#kizami長期記憶) | 会話ベースの長期記憶 |
| [knowledge-rag](TOOLS.md#knowledge-rag知識検索) | RAG ベースのドキュメント検索 |
| [pCloud (rclone)](TOOLS.md#pcloudobsidian-vault-アクセス) | Obsidian Vault への FUSE マウント（WSL2） |

## ファイル構成

| パス | 用途 |
|------|------|
| `CLAUDE.md` | Claude Code グローバル動作原則 |
| `settings.json` | パーミッション設定 |
| `setup.sh` | 新マシン展開オーケストレータ |
| `setup/` | ツール別セットアップモジュール（自動検出・番号プレフィックス順） |
| `docs/` | 手動手順ドキュメント（setup.sh では自動化できない操作） |
| `skills/commit/` | `/commit` スキル |
| `local-plugins/` | ローカルプラグイン群（`~/.claude/local-plugins/` に配置する前提）。`commit-skill` / `pr-review-skill` / `pr-review-respond-skill` / `code-review-command` を含む |
| `agents/` | グローバルサブエージェント定義 |
| `memory/` | クロスセッション知識（自動管理） |
| `TOOLS.md` | 各ツールの詳細・導入確認・保存タイミング |
| `DESIGN.md` | 設計意図・設定の背景・ツール間連携 |

## Git 管理外

`.gitignore` 参照。認証情報・会話履歴・マシン固有データ・RTK 生成物は除外済み。

## 還流手順

実働環境（`~/.claude/`）で追加・変更されたスキルを配布原本（このリポジトリ）に反映する手順。

### de-git（初回のみ）

> SPEC-02-01: 実施は一回限り。PR 作業とは独立した手動操作。

`~/.claude/` が git リポジトリのままだと誤 `git pull` による大量コンフリクトが発生しうる。以下で一回だけ解除する。

```bash
# 前提確認
ls ~/.claude/.git/   # 存在すること

# de-git 実行
rm -rf ~/.claude/.git/

# 事後確認
git -C ~/.claude status 2>&1 | grep "not a git repository"
```

### 還流検知（`/sync-check`）

`/sync-check` スキルで実働環境と配布原本を突合し、還流漏れを検知する。

```bash
~/srcs/Claude-StartUp/scripts/sync-check.sh
```

#### 出力カテゴリと対処

| カテゴリ | 意味 | 対処 |
|---|---|---|
| 要還流（新規） | 実働環境にのみ存在 | ブランチ作成 → `cp` → PR |
| 要還流（変更） | 両側に存在するが差分あり | `diff` で確認 → 有益な変更のみ PR |
| 削除予定（既知） | `sync-known-deletions.conf` に記載 | 対応 core の実装を待つ（還流しない） |
| 同一 | 差分なし（`--verbose` 時のみ表示） | 対応不要 |

### 還流 PR の作成

1. `main` から作業ブランチを作成
2. 実働環境のファイルを配布原本にコピー（`cp -r ~/.claude/skills/foo/ skills/foo/`）
3. PR を作成して merge

### 還流実施タイミング

開発者の判断に委ねる。スキルを追加・変更したタイミングや、定期的なメンテナンスの一環として実施する。
