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

## RTK（Rust Token Killer）

`setup.sh` は [rtk-ai/rtk](https://github.com/rtk-ai/rtk) を自動導入する。Claude Code の PreToolUse hook で `git status` → `rtk git status` のように Bash コマンドを透過的に書き換え、出力を圧縮してトークン消費を 60〜90% 削減する Rust 製 CLI。

導入確認:

```bash
rtk --version          # rtk X.Y.Z が表示されれば OK
rtk gain               # セッションのトークン削減量
rtk gain --history     # 書き換えられたコマンド履歴
```

### PATH 永続化の挙動

`setup.sh` は `~/.local/bin` が PATH に無ければ、`$SHELL` に応じた rc ファイル（`zshrc` / `bashrc` / `profile`）1 本にマーカー付きで 3 行だけ追記する。次回シェル起動から恒久有効。不要な場合は該当 rc の `# Claude-StartUp: local bin (RTK 等)` ブロックを手動削除する。

### rtk init が書き込む差分の扱い

`rtk init -g --auto-patch` は各マシンで以下を書き換えるが、いずれも **環境ごとのローカル状態** のためリポジトリにはコミットしない（`git diff` に残っても無視してよい）:

- `settings.json` に `hooks.PreToolUse` RTK エントリ追加
- `CLAUDE.md` 末尾に `@RTK.md` import 追加
- `RTK.md` 本体生成（`.gitignore` 済み）

### 再セットアップ時の注意（鶏卵問題）

既に Claude Code が起動中のセッションからハーネスを再展開したい場合は、**方式 A（ワンライナー）ではなく 方式 B（`bash setup.sh`）を使う**。`settings.json` の `Bash(curl * | sh)` deny ルールが先に効くため、方式 A は Claude 経由ではブロックされる。新規マシンでの初回セットアップは deny ルールが展開前なので方式 A で問題ない。

## Opus 4.6 の挙動調整

`settings.json` で `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` を設定し、adaptive thinking を無効化している。`effortLevel: high` と adaptive thinking の併用で CLAUDE.md ルールやスキル定義が無視される挙動（[claude-code#23936](https://github.com/anthropics/claude-code/issues/23936)）の回避が目的。

不具合を感じる場合は、`@2.1.98` などの安定版にダウングレードすることも検討する:

```bash
npm install -g @anthropic-ai/claude-code@2.1.98
```

ただしバージョン固定は `setup.sh` には組み込まない（更新を逃す副作用が大きいため、個人判断で実施する）。

## Git 管理外

`.gitignore` 参照。認証情報・会話履歴・マシン固有データ・RTK 生成物は除外済み。
