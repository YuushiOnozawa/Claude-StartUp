# Claude Code Harness

個人用 `~/.claude/` 共通設定。`setup.sh` で新マシンに展開する。

## セットアップ

### 方式 A: ワンライナー（新規マシン推奨）

```bash
curl -fsSL https://raw.githubusercontent.com/YuushiOnozawa/Claude-StartUp/main/setup.sh \
  | bash -s -- https://github.com/YuushiOnozawa/Claude-StartUp.git
```

`~/.claude/` 展開・依存ツール確認・npm グローバルパッケージ（commitlint 等）の自動インストールを一括実行する。

### 方式 B: ローカル clone 済みの場合

```bash
bash setup.sh <repo-url>
```

依存ツール（node / npm / commitlint）の確認と clone を自動処理する。未導入の npm グローバルパッケージは自動インストールする。

## ファイル構成

| パス | 用途 |
|------|------|
| `CLAUDE.md` | Claude Code グローバル動作原則 |
| `settings.json` | パーミッション設定 |
| `setup.sh` | 新マシン展開スクリプト |
| `local-plugins/skills/commit/` | `/commit` スキル |
| `agents/` | グローバルサブエージェント定義 |
| `memory/` | クロスセッション知識（自動管理） |

## Git 管理外

`.gitignore` 参照。認証情報・会話履歴・マシン固有データは除外済み。
