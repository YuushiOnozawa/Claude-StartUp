# Claude Code Harness

個人用 `~/.claude/` 共通設定。`setup.sh` + `setup/` モジュール群で新マシンに展開する。

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
