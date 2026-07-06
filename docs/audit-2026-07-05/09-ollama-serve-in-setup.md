# 09. setup 内での Ollama サーバー起動・常駐化

種別: 不足機能 / 優先度: 高

## 現状

- `setup/401-ollama.sh` は Ollama バイナリのインストールまで。
- `setup/800-ollama-models.sh` は `ollama list` が通らない（= サーバー未起動）と
  **モデル pull を丸ごとスキップ**して正常終了する。
- TOOLS.md にも「事前に `ollama serve` を起動してから setup.sh を実行すること」とあるが、
  ワンライナー展開の文脈ではこの前提が満たされない（新規マシンで最初に走らせるスクリプトのため）。

結果: ワンライナー一発では MAGI 用モデルが1つも入らず、初回レビューは全て
Haiku フォールバック確認ダイアログから始まる。「1スキル1ローカルLLM」と
「ワンライナー展開」という2つの目的が両立しない状態。

## 対応プラン

1. `setup/401-ollama.sh` にサーバー起動処理を追加する。環境判別つき：

   ```bash
   if ollama list &>/dev/null; then
     ok "ollama server (起動済み)"
   elif command -v systemctl &>/dev/null && systemctl list-unit-files ollama.service &>/dev/null; then
     sudo systemctl enable --now ollama   # 公式インストーラは通常 service を登録する
   else
     # WSL 等 systemd なし: バックグラウンド起動して readiness を待つ
     nohup ollama serve >/dev/null 2>&1 &
     for _ in $(seq 1 30); do ollama list &>/dev/null && break; sleep 1; done
   fi
   ```

   起動失敗時は fail + MISSING_CMDS（800 のスキップ理由が明確になる）。
2. `setup/800-ollama-models.sh` のスキップを**警告に格上げ**する: サーバー不達なら
   `MISSING_CMDS+=("ollama-models")` に積み、サマリーで「モデル未取得。`ollama serve` 起動後に
   `bash setup.sh` を再実行」と案内する（現状の `return 0` は成功と見分けがつかない）。
3. Windows 側 Ollama（WSL から Windows ホストの Ollama を使う構成、commit c48711d /
   `hooks/lib/ollama.sh` の `ollama_base_url`）を考慮する: サーバー起動判定は
   `ollama list` 直ではなく `ollama_base_url` 経由の `/api/tags` 到達確認に寄せると、
   ホスト側 Ollama 利用時に WSL 内で二重起動しない。
4. pull の所要時間対策（任意）: モデル合計が数十GBになるため、`SKIP_OLLAMA_MODELS=1` で
   モデル取得を丸ごとスキップできる環境変数を追加し、README に記載する
   （knowledge-rag の `SKIP_OLLAMA_MODEL=1` と命名を揃える）。

## 受け入れ基準

- [ ] 素の新規環境（Ollama 未インストール・未起動）でワンライナー実行 → 完了時に `ollama list` にモデルが揃う
- [ ] Windows ホスト側 Ollama 構成で WSL 内に ollama serve が二重起動しない
- [ ] サーバー起動失敗時、サマリーに明確な再実行手順が出る

## 影響ファイル

- `setup/401-ollama.sh`, `setup/800-ollama-models.sh`
- `hooks/lib/ollama.sh`（`ollama_base_url` の再利用のみ、変更は最小）
- `TOOLS.md` / `README.md`（前提の書き換え）
