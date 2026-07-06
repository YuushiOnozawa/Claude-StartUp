# 14. Windows ネイティブ環境対応

種別: 推奨追加機能 / 優先度: 低（現運用は WSL で成立しているため）

## 現状

- setup.sh / setup/ / hooks/ はすべて bash 前提。Linux/WSL では完結するが、
  Windows ネイティブの Claude Code（PowerShell 環境）には展開できない。
- 一方で現環境は既にハイブリッド構成が始まっている：
  - Windows ホスト側 Ollama を WSL から参照する対応が入っている（`hooks/lib/ollama.sh` の base_url 解決）
  - `.codex/hooks.json` には `commandWindows`（Git Bash 経由）記述が存在する
  - ユーザーの主端末は Windows 11 で、Claude Code デスクトップ利用がある

「新規環境へワンライナー展開」の"環境"に Windows ネイティブを含めるかどうかで
スコープが大きく変わるため、まず方針を決める。

## 対応プラン

### フェーズ 0: 方針決定（これだけ先にやる）

README に「サポート環境」を明記する: 推奨 = WSL2 (Ubuntu)、macOS/Linux = 動作想定、
Windows ネイティブ = 非対応（or 限定対応）。**現状これがどこにも書かれていない**ため、
非対応と決めるだけでも価値がある。

### フェーズ 1（限定対応する場合）: Git Bash 経由の最小対応

- Claude Code for Windows は Git Bash でフックを実行できるため、フル PowerShell 移植は不要。
- 対応内容:
  - hooks/ 内の Linux 依存を洗い出す: `mountpoint`（Git Bash に無い）、`flock`、`notify-send`、
    `$HOME/pcloud` FUSE 前提 — このあたりが Windows で自然に無効化されるよう
    「コマンド不在なら機能スキップ」ガードを追加
  - `setup.ps1`（薄いラッパー）: git clone → `%USERPROFILE%\.claude` 配置 → Git Bash で setup.sh を起動
  - pCloud は rclone mount の代わりに pCloud Drive（ネイティブアプリ）のドライブレターを
    vault-path（13 の設定化）で指す運用に切り替え
- kizami / knowledge-rag / RTK の Windows 対応状況は個別に上流を確認し、非対応のものは
  verify（10）で warn 表示に落とす。

### フェーズ 2（本格対応する場合のみ）

- setup/ モジュールの PowerShell 版並行整備。コストが大きく、WSL 運用で足りている限り非推奨。

## 受け入れ基準

- [ ] README にサポート環境マトリクスが記載されている
- [ ] （フェーズ1採用時）Windows + Git Bash で setup が完走し、非対応機能は明示的に warn される

## 影響ファイル

- `README.md`（フェーズ0）
- （フェーズ1）新規 `setup.ps1`、`hooks/` のガード追記、`docs/windows-setup.md`
