# pCloud セットアップ手順（rclone / WSL2）

WSL2 内で pCloud の Vault ディレクトリにアクセスするための設定手順。

## 前提

- WSL2 (Ubuntu 24.04)
- `setup.sh` 実行済み（rclone インストール・`~/pcloud` マウントポイント作成済み）

> **注意**: apt 版 rclone (v1.60.x) は WSL2 で FUSE マウントが動作しない既知のバグがある。
> `setup.sh` は公式インストーラ (`curl https://rclone.org/install.sh | sudo bash`) を使用する。
> `unzip` が必要: `sudo apt-get install -y unzip`

---

## 1. rclone に pCloud リモートを追加

**初回のみ必要。**

```bash
rclone config
```

対話式の手順：

| プロンプト | 入力 |
|---|---|
| `n/s/q>` | `n` |
| `name>` | `pcloud` |
| `Storage>` | `pcloud` |
| `client_id>` | （空白のまま Enter） |
| `client_secret>` | （空白のまま Enter） |
| Edit advanced config? `y/n` | `n` |
| Use auto config? `y/n` | `n` |

`n` を選んだ後、以下のコマンドを**別のターミナルで実行**する：

```bash
rclone authorize "pcloud"
```

ブラウザが開くので pCloud にログインして認証。  
ターミナルに JSON トークンが表示されたら、元の `config_token>` プロンプトに貼り付ける。

最後に `y` で保存 → `q` で終了。

---

## 2. マウント

```bash
rclone mount pcloud: ~/pcloud --daemon --vfs-cache-mode writes
```

- `~/pcloud/` 以下に pCloud のファイルが表示される
- `--daemon` でバックグラウンド実行

### アンマウント

```bash
fusermount -u ~/pcloud
```

---

## 3. Obsidian Vault への書き込み

マウント後、Vault ディレクトリに直接ファイルを置くだけで pCloud が同期する。

```bash
# Vault のパスを確認
ls ~/pcloud/

# ファイルを書き込む例
echo "# メモ" > ~/pcloud/<Vault名>/note.md
```

Windows・スマホ等の Obsidian が自動的に参照する。

---

## 注意事項

- マウントは WSL セッションをまたいで維持されない場合がある（必要に応じて再マウント）
- `rclone config` の設定は `~/.config/rclone/rclone.conf` に保存される
